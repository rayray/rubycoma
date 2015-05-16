#!/bin/bash

gem uninstall rubycoma &&
gem build rubycoma.gemspec &&
gem install rubycoma-0.12pre.gem &&
ruby test.rb
