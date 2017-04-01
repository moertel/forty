FROM ruby:2.3.1

COPY ./lib lib
COPY ./acl.json acl.json
COPY ./Gemfile Gemfile
COPY ./Rakefile Rakefile
COPY ./forty.gemspec forty.gemspec

RUN bundle install

CMD ["rspec"]
