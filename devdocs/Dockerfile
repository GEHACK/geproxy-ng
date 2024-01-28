FROM ruby:3.3.0
ENV LANG=C.UTF-8
ENV ENABLE_SERVICE_WORKER=true

RUN apt-get update && \
    apt-get -y install git nodejs libcurl4 && \
    gem install bundler && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/freeCodeCamp/devdocs /devdocs
WORKDIR /devdocs
# Checkout a somewhat stable version, devdocs is more rolling release than anything else.
RUN git checkout dc3ad6e4d44f47417b72c7cda33c5308cd67f93f

RUN bundle install --system && \
    rm -rf ~/.gem /root/.bundle/cache /usr/local/bundle/cache

ENV LANGUAGES='openjdk@18 c cpp python@3.10'

EXPOSE 9292

COPY <<EOF /entrypoint.sh
#!/bin/bash

cd /devdocs
thor docs:download ${LANGUAGES}
thor assets:compile

rackup -o 0.0.0.0
EOF

CMD /entrypoint
