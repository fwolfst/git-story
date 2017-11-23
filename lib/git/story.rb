require 'tins/xt'
require 'open-uri'
require 'json'
require 'complex_config'

require 'term/ansicolor'
Term::ANSIColor.coloring = STDOUT.tty?
class String
  include Term::ANSIColor
end


unless defined?(Git)
  module Git
  end
end

module Git::Story
end

require 'git/story/version'
require 'git/story/utils'
require 'git/story/setup'
require 'git/story/semaphore'
require 'git/story/app'
