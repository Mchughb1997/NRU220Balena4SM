FROM 508039614064.dkr.ecr.us-east-1.amazonaws.com/cuda:11.2.2-cudnn8-runtime-ubuntu20.04

WORKDIR /srv/

# Setup localization settings
# Set time to UTC, set builds to run headlessly
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TZ=UTC
ENV DEBIAN_FRONTEND=noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=true
RUN ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo UTC > /etc/timezone

# Update the GPG key for Nvidia repositories
# See https://developer.nvidia.com/blog/updating-the-cuda-linux-gpg-repository-key/
# Process to change over to the new repo is complicated because the base container
# bundles the old keys. This layer will need to be updated with the old GPG key each time it expires.
#
# Steps this layer performs:
# - Remove old repos
# - Remove old keys
# - Install tooling
# - Install new key
# - Reinstall nvidia repo
#
# WTF Nvidia?!?!
RUN rm -f /etc/apt/sources.list.d/cuda.list && \
    rm -f /etc/apt/sources.list.d/cuda-ubuntu2004-x86_64.list && \
    rm -f /etc/apt/sources.list.d/nvidia-ml.list && \
    apt-key del 7fa2af80 && \
    apt-get update -qq && \
    apt-get install -y wget && \
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb && \
    dpkg -i cuda-keyring_1.0-1_all.deb && \
    echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/ /" | tee /etc/apt/sources.list.d/cuda-ubuntu2004-x86_64.list && \
    apt-get update

# Install common dependencies used throughout the build process
# Any any apt dependencies from the default repos to this lay 
RUN apt-get update -qq && \
    apt-get install -y \
    kmod \
    wget \
    gcc \
    nano \
    git \
    curl \
    gnupg2 \
    lsb-release \
    build-essential \
    software-properties-common \
    apt-utils \
    dialog \
    aufs-tools \
    libc-dev \
    iptables \
    conntrack \
    unzip \
    libglu1-mesa-dev \
    libssl-dev \
    cmake \
    dbus \
    libxml2 \
    libglib2.0-0 \
    libgtk2.0-dev \
    pkg-config \
    ffmpeg \
    libavcodec-dev \ 
    libavformat-dev \ 
    libavutil-dev \ 
    libswscale-dev \ 
    libavresample-dev \
    libsm6 \
    libxext6 \
    libcanberra-gtk-module \
    libeigen3-dev \
    libpq-dev \
    libjpeg-dev \
    zlib1g-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-tk \
    bison \
    flex \
    libelf-dev \
    m4 \
    perl \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    less \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Remove gcc-9
RUN apt-get update && apt remove -y gcc-9 \
    && apt purge gcc-9 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install gcc-11 (needed for building the kernel)
RUN add-apt-repository ppa:ubuntu-toolchain-r/test
RUN apt-get update && apt-get install -y gcc-11 g++-11 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 100 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Upgrade to gcc-11.3.0 because the above provides only gcc-11.1.0
RUN wget ftp://ftp.gnu.org/gnu/gcc/gcc-11.3.0/gcc-11.3.0.tar.xz \
    && tar -xf gcc-11.3.0.tar.xz \
    && cd gcc-11.3.0 \
    && ./contrib/download_prerequisites \
    && mkdir build \
    && cd build \
    && ../configure --disable-multilib \
    && make -j2 \
    # && apt purge --autoremove -y gcc-11 \
    # && unlink /usr/bin/cc \
    && make install \
    && export LD_LIBRARY_PATH=/usr/local/lib/gcc/x86_64-pc-linux-gnu/11.3.0:$LD_LIBRARY_PATH \
    && ln -s /usr/local/bin/gcc /usr/bin/cc \
    && cd .. \
    && rm -rf gcc-11.3.0.tar.xz

# Variables defining the machine type, kernel version, and driver version
ARG BALENA_MACHINE_NAME=genericx86-64-ext
ARG BALENAOS_VERSION=2.115.3
ARG YOCTO_VERSION=5.15.54
ENV YOCTO_KERNEL=${YOCTO_VERSION}-yocto-standard

ARG NVIDIA_DRIVER_VERSION=525.116.04
# ARG CUDA_INSTALL_VERSION=11.2.2
ENV NVIDIA_DRIVER_RUN=NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run
ENV DEBIAN_FRONTEND=noninteractive

# Install Nvidia Driver and kernel module headers
# Currently, downloading kernel modules for this OS from https://files.balena-cloud.com/images/genericx86-64-ext/2.115.3/kernel_source.tar.gz
RUN wget -nv -q https://files.balena-cloud.com/images/${BALENA_MACHINE_NAME}/${BALENAOS_VERSION}/kernel_source.tar.gz && \
    tar -xzvf kernel_source.tar.gz && \
    # generate default kernel config 
    make -C ${YOCTO_KERNEL}/build/ olddefconfig && \
    # prepare for building modules, and use gcc-11 matching the compiler the kernel was originally built with # https://www.kernel.org/doc/Documentation/kbuild/modules.txt
    make -C ${YOCTO_KERNEL}/build/ modules_prepare CC=gcc-11 && \    
    ln -s /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2 && \
    wget -nv -q http://us.download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${NVIDIA_DRIVER_RUN} && \
    chmod +x ./${NVIDIA_DRIVER_RUN} && \
    mkdir -p /nvidia && \
    mkdir -p /nvidia/driver && \
    ./${NVIDIA_DRIVER_RUN} \
    --kernel-install-path=/nvidia/driver \
    --ui=none \
    --no-drm \
    --no-questions \
    --no-x-check \
    --install-compat32-libs \
    --no-nouveau-check \
    --no-nvidia-modprobe \
    --no-rpms \
    --no-backup \
    --no-check-for-alternate-installs \
    --no-libglx-indirect \
    --no-install-libglvnd \
    --x-prefix=/tmp/null \
    --x-module-path=/tmp/null \
    --x-library-path=/tmp/null \
    --x-sysconfig-path=/tmp/null \
    --kernel-source-path=$(readlink -f ${YOCTO_KERNEL}/build) \
    && rm -rf /tmp/* ${NVIDIA_DRIVER_RUN} kernel_source.tar.gz

# Add CUDA to linker path
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64/
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-11.2/lib64/:/usr/local/cuda-11.1/lib64/
ENV PATH=$PATH:/usr/local/cuda-11.2/bin:/usr/local/cuda/bin

# Update python3 + pip
RUN pip3 install --upgrade pip

# Install tensorflow and tensorRT
RUN wget -q https://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1804/x86_64/libnvinfer7_7.2.2-1+cuda11.1_amd64.deb && \
    wget -q https://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1804/x86_64/libnvinfer-plugin7_7.2.2-1+cuda11.1_amd64.deb && \
    apt update && \
    apt install cuda-nvrtc-11-1 && \
    dpkg -i libnvinfer7_7.2.2-1+cuda11.1_amd64.deb && \
    dpkg -i libnvinfer-plugin7_7.2.2-1+cuda11.1_amd64.deb

RUN pip3 install nvidia-pyindex && \
    pip3 install tensorflow-gpu==2.8.0 && \
    pip3 install nvidia-tensorrt==7.2.2.1

# Install other libraries
RUN apt-get update -qq && apt-get install -y \
    libopencv-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-base \
    gstreamer1.0-libav \
    libcurl4-openssl-dev \
    libcurlpp-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Build OpenCV 4.1.0 from source, including gstreamer and ffmpeg
RUN cd /home/ \
    && wget -q https://github.com/opencv/opencv/archive/4.1.0.zip \
    && unzip 4.1.0.zip \
    && rm 4.1.0.zip \
    && cd /home/opencv-4.1.0 \
    && mkdir build \
    && cd build \
    && cmake \
    -D CMAKE_BUILD_TYPE=RELEASE \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D BUILD_opencv_python2=OFF \
    -D BUILD_opencv_python3=ON \
    -D OPENCV_GENERATE_PKGCONFIG=ON \
    -D OPENCV_PC_FILE_NAME=opencv.pc \
    -D WITH_GSTREAMER=ON \
    -D WITH_FFMPEG=ON \
    -D BUILD_PERF_TESTS=OFF \
    -D BUILD_TESTS=OFF ../ \ 
    && make -j4 \
    && make install \
    && ldconfig \
    && cd .. \
    && rm -rf build \
    && rm -rf /home/opencv-4.1.0

# Install ROS2 Galactic
SHELL ["/bin/bash", "-c"]
RUN apt-get update -qq && apt-get install -y curl gnupg2 lsb-release \
    && curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add - \
    && echo "deb [arch=$(dpkg --print-architecture)] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/ros2-latest.list \
    && apt-get update \
    && apt-get install -y \
    ros-galactic-ros-base \
    ros-galactic-rmw-cyclonedds-cpp \
    ros-galactic-cv-bridge \
    ros-galactic-tf-transformations \
    && source /opt/ros/galactic/setup.bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Build and install nlohmann-json3-dev
RUN cd /home/ \
    && wget https://github.com/nlohmann/json/archive/refs/tags/v3.10.2.tar.gz \ 
    && tar -xzf v3.10.2.tar.gz \
    && cd json-3.10.2/ \
    && cmake . \
    && make -j8 \
    && make install

RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 40976EAF437D05B5
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32

# Build and install pybind11 and pybind11_json
RUN apt-get update -qq \
    && apt-get install -y python3-dev \
    && cd /home/ \
    && wget https://github.com/pybind/pybind11/archive/refs/tags/v2.7.1.tar.gz \
    && tar -xzf v2.7.1.tar.gz \
    && cd pybind11-2.7.1 \
    && cmake . \
    && make -j8 \
    && make install \
    && cd /home/ \
    && wget https://github.com/pybind/pybind11_json/archive/refs/tags/0.2.11.tar.gz \
    && tar -xzf 0.2.11.tar.gz \
    && cd pybind11_json-0.2.11/ \
    && cmake . \
    && make -j8 \
    && make install \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install libv4l1.so.0 for protech tracker
RUN apt-get update && apt-get install -y libv4l-dev

# Install pip requirements for Percy
COPY requirements.txt /srv/
RUN pip3 install -r requirements.txt

# add Percy source files
COPY ./config config
COPY ./scripts scripts
COPY ./src src

# Security
COPY ./resources/security/vault_crypto /srv/

# Configure ROS2 middleware and environment settings
COPY ./resources/cyclone /cyclone/
ENV UDEV '1'
ENV ROS_DOMAIN_ID '2'
ENV ROS_LOCALHOST_ONLY '1'
ENV RMW_IMPLEMENTATION 'rmw_cyclonedds_cpp'
ENV CYCLONEDDS_URI '/cyclone/cyclonedds.xml'

# build native drivers
# SHELL ["/bin/bash", "-c"]
RUN mkdir -p /srv/src/smr_percy_sensors/smr_percy_sensors/build && cd /srv/src/smr_percy_sensors/smr_percy_sensors/build \
    && echo 'export PYTHONPATH=/usr/local/lib/python3/dist-packages/:/usr/local/python/' >> ~/.bashrc \
    # enable non-interactive shell
    && sed -i 's/\[ -z "\$PS1" ]/# \[ -z "\$PS1" ]/g' ~/.bashrc \
    && source ~/.bashrc \
    && cmake ../ \
    && make -j8 \
    && make install \
    && ldconfig

# Install requirements for Percy submodules
RUN pip3 install --upgrade pip
RUN cd /srv/src/smr_percy_classifier && python3 -m pip install --user -e .
RUN cd /srv/src/smr_percy_detector && python3 -m pip install --user -e .
RUN cd /srv/src/smr_percy_geolocator && python3 -m pip install --user -e .
RUN cd /srv/src/smr_percy_interfaces && python3 -m pip install --user -e .
RUN cd /srv/src/smr_percy_tracker && python3 -m pip install --user -e .
RUN cd /srv/src/smr_percy_stabilizer && python3 -m pip install --user -e .
RUN cd /srv/src/smr_percy_sensors && python3 -m pip install --user -e .
RUN cd /srv/src/smr_percy_utils && python3 -m pip install --user -e .

# Setup bash so it loads ROS when in interactive shell
RUN echo 'source /opt/ros/galactic/setup.bash' >> /root/.bashrc

HEALTHCHECK --interval=2m --timeout=10s --retries=2 --start-period=1m CMD python3 /srv/scripts/healthcheck.py || bash -c 'kill -s 15 -1 && (sleep 10; kill -s 9 -1)'

CMD ["bash", "/srv/scripts/docker_entrypoint.sh"]
