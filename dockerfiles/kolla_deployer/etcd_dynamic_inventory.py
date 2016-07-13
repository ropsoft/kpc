#! /usr/bin/env python

'''
etcd dynamic inventory script - found at: https://gist.github.com/justenwalker/09698cfd6c3a6a49075b
=================================

Generarates inventory for ansible from etcd using python-etcd library.

The script assumes etcd.ini to be present alongside it. To choose a different
path, set the ETCD_INI_PATH environment variable:

    export ETCD_INI_PATH=/path/to/etcd.ini

All etcd variables are prefixed with /ansible by default, but this can be changed
in the etcd.ini file.

Some example keys to get an idea of how to store your data in etcd (assume prefix is '/ansible'):

## Group Variables
    
    {prefix}/groupvars/{group}/{key}
    
    Example:
    /ansible/groupvars/group1/foo
    

## Host Variables

    {prefix}/hostvars/{host}/{key}
    
    Example:
    /ansible/hostvars/host1/foo

## Host group membership

    {prefix}/hosts/{group}/{host}
    
    Example:
    /ansible/hosts/group1/host1

## Group children

    {prefix}/groups/{parent}/{child}
    
    Example:
    /ansible/groups/group1/group2

'''

import sys
import os
import argparse
import re
from time import time
import ConfigParser

try:
  import json
except ImportError:
  import simplejson as json

try:
  import etcd
except ImportError:
  raise ImportError("python-etcd library is required")

class EtcdInventory:
  def _empty_inventory(self):
    return { '_meta': { 'hostvars': {} } }

  def __init__(self):
    ''' Main execution path '''
    self.inventory = self._empty_inventory()

    # Read settings and parse CLI arguments
    
    self.read_settings()
    self.parse_cli_args()
    
    # Cache
    if self.cache_enabled:
      if self.args.refresh_cache:
          self.refresh_cache()
      elif not self.is_cache_valid():
          self.refresh_cache()
      if self.inventory == self._empty_inventory():
        self.load_from_cache()
    else:
      self.get_inventory()

    # Data to print
    if self.args.host:
        data_to_print = self.get_host_info()
    elif self.args.list:
        data_to_print = self.json_format_dict(self.inventory, True)

    print data_to_print

  def get_host_info(self):
    ''' Get the hostvars for the given --host arg '''
    host = self.args.host
    hostvars = self.inventory['_meta']['hostvars']
    if host in hostvars:
      return self.json_format_dict(hostvars[host],True)
    return self.json_format_dict({}, True)

  def parse_cli_args(self):
    ''' Command line argument processing '''

    parser = argparse.ArgumentParser(description='Produce an Ansible Inventory file based on etcd')
    parser.add_argument('--list', action='store_true', default=True,
                       help='List instances (default: True)')
    parser.add_argument('--host', action='store',
                       help='Get all the variables about a specific instance')
    parser.add_argument('--refresh-cache', action='store_true', default=False,
                       help='Force refresh of cache by making API requests to etcd (default: False - use cache files)')
    self.args = parser.parse_args()

  def is_cache_valid(self):
    ''' Determines if the cache files have expired, or if it is still valid '''

    if os.path.isfile(self.cache_path_cache):
      mod_time = os.path.getmtime(self.cache_path_cache)
      current_time = time()
      if (mod_time + self.cache_max_age) > current_time:
        return True
    return False

  def read_settings(self):
    ''' Reads the settings from the etcd.ini file '''

    config = ConfigParser.SafeConfigParser()
    etcd_default_ini_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'etcd.ini')
    etcd_default_cache_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'etcd.cache')
    etcd_ini_path = os.environ.get('ETCD_INI_PATH', etcd_default_ini_path)
    config.read(etcd_ini_path)

    # Some sensible defaults
    self.prefix = '/ansible'
    self.host = 'localhost'
    self.port = 4001
    self.proto = 'http'
    self.ca_cert = None
    self.cert = None
    self.cache_max_age = 300
    self.cache_enabled = True
    self.cache_dir = os.path.expanduser('~/.ansible/tmp')
    secure = False
    
    # Connection to etcd
    if config.has_option('etcd','host'):
      self.host =  config.get('etcd','host')

    if config.has_option('etcd','port'):
      self.port =  config.getint('etcd','port')

    if config.has_option('etcd','secure'):
      secure = config.getboolean('etcd','secure')

    if secure:
      self.proto = 'https'
      if config.has_option('etcd','ca_cert'):
        self.ca_cert = config.get('etcd','ca_cert')
      if config.has_option('etcd','client_cert') and config.has_option('etcd','client_key'):
        self.cert = (config.get('etcd','client_cert'),config.get('etcd','client_key'))

    # Cache related
    if config.has_option('cache','enabled'):
      self.cache_enabled = config.getboolean('cache','enabled')
    
    if config.has_option('cache','path'):
      self.cache_dir = os.path.expanduser(config.get('cache', 'path'))

    self.cache_path_cache = self.cache_dir + "/ansible-etcd.cache"

    if config.has_option('cache','max_age'):
      self.cache_max_age = config.getint('cache', 'max_age')

  def add_group(self,group):
    if group not in self.inventory:
      self.inventory[group] = { 'hosts': [], 'vars': {}, 'children': [] }

  def get_inventory(self):
    ''' Get inventory from etcd '''
    client = etcd.Client(host=self.host,port=self.port,protocol=self.proto,ca_cert=self.ca_cert,cert=self.cert)
    try:
      inventory  = client.read(self.prefix,recursive=True)
    except KeyError as e:
      raise Exception("Unable read inventory; " + str(e))
    except Exception as e:
      msg = str(e)
      if "alert bad certificate" in msg:
        raise Exception("Make sure client_cert and client_key are set correctly; " + msg)
      if "No JSON object could be decoded" in msg:
        raise Exception("Double check your secure = true setting; " + msg)
      if "No more machines in the cluster" in msg:
        raise Exception("Are your host and port correct?; " + msg)
      raise
    self.inventory = self._empty_inventory()
    for i in inventory.leaves:
      prefix = self.prefix + '/'
      relpath = i.key[len(prefix):]
      path_parts = relpath.split('/')
      t = path_parts[0]

      if len(path_parts) != 3:
        continue

      # Host Variables
      if t == 'hostvars':
        _,host,key = path_parts
        if host not in self.inventory['_meta']['hostvars']:
          self.inventory['_meta']['hostvars'][host] = {}
        self.inventory['_meta']['hostvars'][host][key] = i.value

      ## Add group variables
      if t == 'groupvars':
        _,group,key = path_parts
        self.add_group(group)
        self.inventory[group]['vars'][key] = i.value
      
      # Add host to group
      if t == 'hosts':
        _,group,host = path_parts
        self.add_group(group)
        self.inventory[group]['hosts'].append(host)

      # Group children
      if t == 'groups':
        _,group,child = path_parts
        self.add_group(group)
        self.inventory[group]['children'].append(child)

  def refresh_cache(self):
    ''' Get inventory from etcd and refresh the cache files '''

    self.get_inventory()
    if not os.path.exists(self.cache_dir):
      os.makedirs(self.cache_dir)
    json_data = self.json_format_dict(self.inventory, True)
    cache = open(self.cache_path_cache, 'w')
    cache.write(json_data)
    cache.close()

  def load_from_cache(self):
    ''' Reads the cached inventory file sets self.inventory '''

    cache = open(self.cache_path_cache, 'r')
    json_inventory = cache.read()
    self.inventory = json.loads(json_inventory)

  def json_format_dict(self, data, pretty=False):
    ''' Converts a dict to a JSON object and dumps it as a formatted string '''

    if pretty:
      return json.dumps(data, sort_keys=True, indent=2)
    else:
      return json.dumps(data)

EtcdInventory()
