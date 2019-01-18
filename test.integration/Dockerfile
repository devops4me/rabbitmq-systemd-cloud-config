
# --->
# ---> Going with Ubuntu's Long Term Support (lts)
# ---> version which is currently 18.04.
# --->

FROM ubuntu:18.04


# --->
# ---> As root install git and terraform to test
# ---> this infrastructure module.
# --->

USER root

RUN apt-get update && apt-get --assume-yes install -qq -o=Dpkg::Use-Pty=0 \
      curl  \
      git   \
      unzip

# --->
# ---> Install the Terraform binary.
# --->

RUN \
    curl -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/0.11.9/terraform_0.11.9_linux_amd64.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin && \
    chmod a+x /usr/local/bin/terraform         && \
    rm /tmp/terraform.zip                      && \
    terraform --version


USER ubuntu
WORKDIR /home/ubuntu
