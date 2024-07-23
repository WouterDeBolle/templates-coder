FROM ubuntu

RUN apt-get update \
	&& apt-get install -y \
		curl \
	git \
	sudo \
	software-properties-common \
	vim \
	wget \
	less \
	
	lsof \
	net-tools \
	x11-apps \
	xorg \
	openbox \

	unzip \
	libxext6 \
	libxrender1 \
	libxtst6 \
	libfreetype6 \
	libxi6 \
	x11-xserver-utils \
	python3-tk \
	python3-venv \
	pip \
	&& rm -rf /var/lib/apt/lists/*

ARG USER=coder

ENV DISPLAY=:0

RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
	&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
	&& chmod 0440 /etc/sudoers.d/${USER}
USER ${USER}
WORKDIR /home/${USER}
