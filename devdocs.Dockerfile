FROM ruby:3.2.2
ENV LANG=C.UTF-8
ENV ENABLE_SERVICE_WORKER=true

RUN apt-get update && \
    apt-get -y install git nodejs libcurl4 && \
    gem install bundler && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/freeCodeCamp/devdocs /devdocs
WORKDIR /devdocs

RUN bundle install --system && \
    rm -rf ~/.gem /root/.bundle/cache /usr/local/bundle/cache

ARG languages='openjdk@18 c cpp python@3.10'
RUN thor docs:download $languages && \
    thor assets:compile && \
    rm -rf /tmp

EXPOSE 9292
CMD rackup -o 0.0.0.0
