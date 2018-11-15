FROM centos:latest

COPY docker_scripts/. .
RUN yum -y update
RUN yum install -y java-1.8.0-openjdk vim-enhanced wget tmux libcurl openssl telnet bind-utils perl-JSON-PP nmap-ncat xmail
COPY mongodb-org-3.4.repo /etc/yum.repos.d/mongodb-org-3.4.repo
RUN yum install -y mongodb-org
RUN python get-pip.py
RUN pip install awscli
