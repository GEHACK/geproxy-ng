FROM ruby:2.7.6

ENV LANG=C.UTF-8
ENV ENABLE_SERVICE_WORKER=true

RUN apt-get update
RUN apt-get -y install git nodejs libcurl4
RUN gem install bundler
RUN rm -rf /var/lib/apt/lists/*

ARG languages='openjdk@18 c cpp python@3.10'
RUN git clone https://github.com/freeCodeCamp/devdocs /devdocs
WORKDIR /devdocs

RUN bundle install --system && \
    rm -rf ~/.gem /root/.bundle/cache /usr/local/bundle/cache

RUN thor docs:download $languages
RUN thor assets:compile
RUN rm -rf /tmp

EXPOSE 9292
CMD rackup -o 0.0.0.0
