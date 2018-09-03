# -*- encoding: utf-8 -*-
# stub: git-story-workflow 0.5.3 ruby lib

Gem::Specification.new do |s|
  s.name = "git-story-workflow".freeze
  s.version = "0.5.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Florian Frank".freeze]
  s.date = "2018-09-03"
  s.description = "Gem abstracting a git workflow\u2026".freeze
  s.email = "flori@ping.de".freeze
  s.executables = ["git-story".freeze]
  s.extra_rdoc_files = ["README.md".freeze, "lib/git/story.rb".freeze, "lib/git/story/app.rb".freeze, "lib/git/story/semaphore.rb".freeze, "lib/git/story/setup.rb".freeze, "lib/git/story/utils.rb".freeze, "lib/git/story/version.rb".freeze]
  s.files = [".gitignore".freeze, "COPYING".freeze, "Gemfile".freeze, "README.md".freeze, "Rakefile".freeze, "VERSION".freeze, "bin/git-story".freeze, "config/story.yml".freeze, "git-story-workflow.gemspec".freeze, "lib/git/story.rb".freeze, "lib/git/story/app.rb".freeze, "lib/git/story/prepare-commit-msg".freeze, "lib/git/story/semaphore.rb".freeze, "lib/git/story/setup.rb".freeze, "lib/git/story/utils.rb".freeze, "lib/git/story/version.rb".freeze, "spec/git/story/app_spec.rb".freeze, "spec/spec_helper.rb".freeze]
  s.homepage = "http://flori.github.com/git-story-workflow".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.rdoc_options = ["--title".freeze, "Git-story-workflow".freeze, "--main".freeze, "README.md".freeze]
  s.rubygems_version = "2.7.6".freeze
  s.summary = "Gem abstracting a git workflow".freeze
  s.test_files = ["spec/git/story/app_spec.rb".freeze, "spec/spec_helper.rb".freeze]

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<gem_hadar>.freeze, ["~> 1.9.1"])
      s.add_development_dependency(%q<rake>.freeze, [">= 0"])
      s.add_development_dependency(%q<simplecov>.freeze, [">= 0"])
      s.add_development_dependency(%q<rspec>.freeze, [">= 0"])
      s.add_runtime_dependency(%q<infobar>.freeze, [">= 0"])
      s.add_runtime_dependency(%q<tins>.freeze, [">= 0"])
      s.add_runtime_dependency(%q<mize>.freeze, [">= 0"])
      s.add_runtime_dependency(%q<term-ansicolor>.freeze, [">= 0"])
      s.add_runtime_dependency(%q<complex_config>.freeze, [">= 0"])
    else
      s.add_dependency(%q<gem_hadar>.freeze, ["~> 1.9.1"])
      s.add_dependency(%q<rake>.freeze, [">= 0"])
      s.add_dependency(%q<simplecov>.freeze, [">= 0"])
      s.add_dependency(%q<rspec>.freeze, [">= 0"])
      s.add_dependency(%q<infobar>.freeze, [">= 0"])
      s.add_dependency(%q<tins>.freeze, [">= 0"])
      s.add_dependency(%q<mize>.freeze, [">= 0"])
      s.add_dependency(%q<term-ansicolor>.freeze, [">= 0"])
      s.add_dependency(%q<complex_config>.freeze, [">= 0"])
    end
  else
    s.add_dependency(%q<gem_hadar>.freeze, ["~> 1.9.1"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<simplecov>.freeze, [">= 0"])
    s.add_dependency(%q<rspec>.freeze, [">= 0"])
    s.add_dependency(%q<infobar>.freeze, [">= 0"])
    s.add_dependency(%q<tins>.freeze, [">= 0"])
    s.add_dependency(%q<mize>.freeze, [">= 0"])
    s.add_dependency(%q<term-ansicolor>.freeze, [">= 0"])
    s.add_dependency(%q<complex_config>.freeze, [">= 0"])
  end
end
