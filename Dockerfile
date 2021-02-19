FROM centos:latest

RUN yum -y update
RUN yum install -y java-1.8.0-openjdk vim-enhanced wget tmux libcurl openssl telnet bind-utils perl-JSON-PP nmap-ncat zip unzip
COPY docker_scripts/mongodb-org-3.4.repo /etc/yum.repos.d/mongodb-org-3.4.repo
RUN yum install -y mongodb-org
COPY docker_scripts/get-pip.py .
RUN python get-pip.py
RUN pip install awscli
