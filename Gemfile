# frozen_string_literal: true
#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
#
# This file is part of Flight Job.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Job is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Job. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Job, please visit:
# https://github.com/openflighthpc/flight-job
#==============================================================================
source 'https://rubygems.org'

gem 'commander-openflighthpc', '~> 2.1'
gem 'activemodel'
gem 'flight_configuration', github: 'openflighthpc/flight_configuration', tag: '0.6.3'
gem 'flight-subprocess', github: 'openflighthpc/flight-subprocess', tag: '0.1.4'
gem 'dotenv'
gem 'json_schemer'
gem 'output_mode', '~> 1.7.1'
gem 'pastel'
gem 'tty-markdown'
gem 'tty-editor'
gem 'tty-table', github: 'openflighthpc/tty-table', branch: '9b326fcbe04968463da58c000fbb1dd5ce178243'
gem 'tty-prompt'
gem 'word_wrap'

group :development do
  gem 'pry'
  gem 'pry-byebug'
end

group :test do
  gem 'rspec'
  gem 'fakefs'

  # Used by CI platform
  gem 'rspec_junit_formatter'
  gem 'simplecov', require: false
end
