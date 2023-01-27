# Dockerfile for ATPW
# Last modified: fre jan 27, 2023  05:03
# Sign: JN
# $ docker build -t 'atpw' .

FROM ubuntu:20.04

LABEL version="0.8.0" description="ATPW: Align-and-trees-parallel-workflow"

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C
ENV ATPWHOME=/opt/ATPW
ENV ATPWBIN "${ATPWHOME}/bin"
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV ATPWHOME=/opt/ATPW
ENV ATPWBIN=/opt/ATPW/bin
ENV PYTHON_VERSION=3.8
ENV RAXML_VERSION=1.1.0
ENV BMGE_VERSION=1.12
ENV BMGEJAR "${ATPWHOME}/BMGE-${BMGE_VERSION}/BMGE.jar"
ENV PARGENES "${ATPWHOME}/ParGenes/pargenes/pargenes.py"
ENV TREESHRINK "${ATPWHOME}/TreeShrink/run_treeshrink.py"
ENV PATH "${ATPWBIN}:${PATH}:${ATPWHOME}/ParGenes/pargenes/pargenes_binaries"

WORKDIR .

COPY align-and-trees-parallel-workflow.sh .

RUN \
    apt-get update && apt-get -y --no-install-recommends install \
    apt-utils \
    bc \
    bison \
    build-essential \
    cmake \
    coreutils \
    curl \
    default-jre \
    flex \
    git \
    liblist-moreutils-perl \
    libopenmpi-dev \
    mafft \
    parallel \
    perl \
    pigz \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python3-setuptools \
    r-base-dev=3.6.3-2 \
    unzip \
    vim \
    wget \
    && ln -s /usr/bin/python${PYTHON_VERSION} /usr/bin/python \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN \
    mkdir -p ${ATPWHOME}/bin \
    && mv /align-and-trees-parallel-workflow.sh ${ATPWBIN}/ \
    && chmod +x ${ATPWBIN}/align-and-trees-parallel-workflow.sh \
    && cd ${ATPWHOME} \
    && wget "https://github.com/amkozlov/raxml-ng/releases/download/${RAXML_VERSION}/raxml-ng_v${RAXML_VERSION}_linux_x86_64.zip" \
    && unzip -p raxml-ng_v${RAXML_VERSION}_linux_x86_64.zip raxml-ng > ${ATPWBIN}/raxml-ng \
    && chmod +x ${ATPWBIN}/raxml-ng \
    && rm raxml-ng_v${RAXML_VERSION}_linux_x86_64.zip \
    && git clone https://github.com/uym2/TreeShrink.git \
    && cd TreeShrink \
    && bash ./install_BMS.sh \
    && python setup.py install \
    && chmod +x run_treeshrink.py \
    && cd ${ATPWHOME} \
    && git clone https://github.com/nylander/fastagap.git \
    && cp fastagap/fastagap.pl ${ATPWBIN}/ \
    && chmod +x ${ATPWBIN}/fastagap.pl \
    && wget http://ftp.pasteur.fr/pub/gensoft/projects/BMGE/BMGE-${BMGE_VERSION}.tar.gz \
    && tar xzf BMGE-${BMGE_VERSION}.tar.gz \
    && rm BMGE-${BMGE_VERSION}.tar.gz \
    && git config --global --add safe.directory /opt/ATPW/ParGenes \
    && git clone --recursive https://github.com/BenoitMorel/ParGenes.git \
    && cd ParGenes \
    && ./install.sh \
    && chmod -R o+rX ${ATPWHOME}/ParGenes/pargenes/pargenes_binaries/*

    #R --slave -e 'install.packages(c("ape", "PBD", "BMS"), repos="https://cloud.r-project.org/")'

ENTRYPOINT ["align-and-trees-parallel-workflow.sh"]

CMD ["-h"]

