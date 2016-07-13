FROM ubuntu:xenial

RUN apt-get -q -y update && \
    apt-get -q -y purge python-pip && \
    apt-get -q -y install curl python-dev gcc libffi-dev libssl-dev inetutils-ping ntp vim wget && \
    curl https://bootstrap.pypa.io/get-pip.py | python && \
    curl -sSL https://get.docker.io | bash && \
    pip install -U ansible==1.9.4 oauth && \
    #pip install -U ansible==1.9.4 oauth docker-py && \
    git clone --branch stable/mitaka https://git.openstack.org/openstack/kolla && \
    pip install kolla/ && \
    cp -r kolla/etc/kolla /etc/ && \
    kolla-genpwd && \
    # remove hosts (control01, network02, etc.) since we're using dynamic inventory... but preserve groups
    grep -v 'control[^] -]\|network[^] -]\|compute[^] -]\|storage[^] -]' /usr/local/share/kolla/ansible/inventory/multinode > /usr/local/share/kolla/ansible/inventory/kolla_groups && \
    rm /usr/local/share/kolla/ansible/inventory/all-in-one && \
    rm /usr/local/share/kolla/ansible/inventory/multinode

ADD etcd_dynamic_inventory.py /usr/local/share/kolla/ansible/inventory
ADD .bash_profile /root
ADD post_pxe_hostprep.yml /root

RUN chmod 755 /usr/local/share/kolla/ansible/inventory/etcd_dynamic_inventory.py

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["bash -l"]
