FROM ubuntu:xenial

RUN apt-get -q -y update && \
    apt-get -q -y purge python-pip && \
    apt-get -q -y install curl python-dev gcc libffi-dev libssl-dev inetutils-ping ntp vim wget && \
    curl https://bootstrap.pypa.io/get-pip.py | python && \
    curl -sSL https://get.docker.io | bash && \
    pip install -U ansible==1.9.4 oauth docker-py && \
    git clone --branch stable/mitaka https://git.openstack.org/openstack/kolla && \
    pip install python-etcd kolla/ && \
    cp -r kolla/etc/kolla /etc/ && \
    kolla-genpwd && \
    # remove hosts (control01, network02, etc.) since we're using dynamic inventory... but preserve groups
    grep -v 'control[^] -]\|network[^] -]\|compute[^] -]\|storage[^] -]' /usr/local/share/kolla/ansible/inventory/multinode > /usr/local/share/kolla/ansible/inventory/kolla_groups && \
    rm /usr/local/share/kolla/ansible/inventory/all-in-one && \
    #rm /usr/local/share/kolla/ansible/inventory/multinode
    mv /usr/local/share/kolla/ansible/inventory/multinode /root

ADD etcd_inv.py /usr/local/share/kolla/ansible/inventory
ADD etcd.ini /root

RUN chmod 755 /usr/local/share/kolla/ansible/inventory/etcd_inv.py

# needed for ansible to bootstrap coreos for control
RUN ansible-galaxy install defunctzombie.coreos-bootstrap

ENV ETCD_INI_PATH /root/etcd.ini

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["bash -l"]
