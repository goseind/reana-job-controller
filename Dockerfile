# This file is part of REANA.
# Copyright (C) 2017, 2018, 2019, 2020, 2021, 2022, 2023 CERN.
#
# REANA is free software; you can redistribute it and/or modify it
# under the terms of the MIT License; see LICENSE file for more details.

# Use Ubuntu LTS base image
FROM ubuntu:20.04

# Use default answers in installation commands
ENV DEBIAN_FRONTEND=noninteractive

# Prepare list of Python dependencies
COPY requirements.txt /code/

# Install all system and Python dependencies in one go
# hadolint ignore=DL3008,DL3013
RUN apt-get update -y && \
    apt-get install --no-install-recommends -y \
      gcc \
      krb5-config \
      krb5-user \
      libauthen-krb5-perl \
      libkrb5-dev \
      openssh-client \
      python3-pip \
      python3.8 \
      python3.8-dev \
      vim-tiny && \
    pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /code/requirements.txt && \
    apt-get remove -y \
      gcc && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Default compute backend is Kubernetes
ARG COMPUTE_BACKENDS=kubernetes

# Install CERN HTCondor compute backend dependencies (if necessary)
# hadolint ignore=DL3008,DL4006
RUN if echo "$COMPUTE_BACKENDS" | grep -q "htcondorcern"; then \
      set -e; \
      apt-get update -y; \
      apt-get install --no-install-recommends -y wget alien gnupg2 rand; \
      wget -O ngbauth-submit.rpm https://linuxsoft.cern.ch/internal/repos/batch8s-stable/x86_64/os/Packages/ngbauth-submit-0.26-2.el8s.noarch.rpm; \
      wget -O myschedd.rpm https://linuxsoft.cern.ch/internal/repos/batch8s-stable/x86_64/os/Packages/myschedd-1.9-2.el8s.x86_64.rpm; \
      yes | alien -i myschedd.rpm; \
      yes | alien -i ngbauth-submit.rpm; \
      rm -rf myschedd.rpm ngbauth-submit.rpm; \
      wget -qO - https://research.cs.wisc.edu/htcondor/ubuntu/HTCondor-Release.gpg.key | apt-key add -; \
      echo "deb http://research.cs.wisc.edu/htcondor/ubuntu/8.9/focal focal contrib" >> /etc/apt/sources.list; \
      echo "deb-src http://research.cs.wisc.edu/htcondor/ubuntu/8.9/focal focal contrib" >> /etc/apt/sources.list; \
      apt-get update -y; \
      apt-get install --no-install-recommends -y condor; \
      apt-get remove -y gnupg2 wget alien; \
      apt-get autoremove -y; \
      apt-get clean; \
      rm -rf /var/lib/apt/lists/*; \
    fi

# Copy Kerberos related configuration files
COPY etc/krb5.conf /etc/krb5.conf

# Copy CERN HTCondor compute backend related configuration files
RUN mkdir -p /etc/myschedd
COPY etc/myschedd.yaml /etc/myschedd/
COPY etc/10_cernsubmit.config /etc/condor/config.d/
COPY etc/10_cernsubmit.erb /etc/condor/config.d/
COPY etc/ngbauth-submit /etc/sysconfig/
COPY etc/ngauth_batch_crypt_pub.pem /etc/
COPY etc/cerngridca.crt /usr/local/share/ca-certificates/cerngridca.crt
COPY etc/cernroot.crt /usr/local/share/ca-certificates/cernroot.crt
COPY etc/job_wrapper.sh etc/job_wrapper.sh
RUN chmod +x /etc/job_wrapper.sh
RUN update-ca-certificates

# Copy cluster component source code
WORKDIR /code
COPY . /code

# Are we debugging?
ARG DEBUG=0
RUN if [ "${DEBUG}" -gt 0 ]; then pip install -e ".[debug]"; else pip install .; fi;

# Are we building with locally-checked-out shared modules?
# hadolint ignore=SC2102
RUN if test -e modules/reana-commons; then pip install -e modules/reana-commons[kubernetes] --upgrade; fi
RUN if test -e modules/reana-db; then pip install -e modules/reana-db --upgrade; fi

# Check for any broken Python dependencies
RUN pip check

# Set useful environment variables
ENV COMPUTE_BACKENDS=$COMPUTE_BACKENDS \
    FLASK_APP=reana_job_controller/app.py \
    TERM=xterm

# Expose ports to clients
EXPOSE 5000

# Run server
CMD ["flask", "run", "-h", "0.0.0.0"]
