FROM centos:7

RUN yum -y update
RUN yum -y install epel-release
RUN yum -y install python-pip
RUN yum install -y java-1.8.0-openjdk vim-enhanced wget tmux libcurl openssl telnet bind-utils perl-JSON-PP nmap-ncat zip unzip --skip-broken
COPY docker_scripts/mongodb-org-3.4.repo /etc/yum.repos.d/mongodb-org-3.4.repo
RUN yum install -y mongodb-org
RUN pip install awscli
