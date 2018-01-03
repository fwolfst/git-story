require 'time'
require 'open-uri'

class Git::Story::App
  class ::String
    include Term::ANSIColor
  end

  include Tins::GO
  include Git::Story::Utils
  extend Git::Story::Utils
  include ComplexConfig::Provider::Shortcuts

  annotate :command

  BRANCH_NAME_REGEX = /\A(?:story|feature)_([a-z0-9-]+)_(\d+)(?:\-[0-9a-f]+)?\z/

  module StoryAccessors
    attr_accessor :story_name

    attr_accessor :story_base_name

    attr_accessor :story_id

    attr_accessor :story_created_at

    attr_accessor :story_author
  end

  def initialize(argv = ARGV, debug: ENV['DEBUG'].to_i == 1)
    @argv    = argv
    @command = @argv.shift&.to_sym
    @debug   = debug
  end

  def run
    Git::Story::Setup.perform
    if command_of(@command)
      puts __send__(@command, *@argv)
    else
      @command and @command = @command.inspect
      @command ||= 'n/a'
      STDERR.puts "Unknown command #{@command}\n\n#{help.join(?\n)}"
      exit 1
    end
  rescue Errno::EPIPE
  end

  command doc: 'this help'
  def help
    result = [ 'Available commands are:' ]
    longest = command_annotations.keys.map(&:size).max
    result.concat(
      command_annotations.map { |name, a|
        "#{name.to_s.ljust(longest)} #{a[:doc]}"
      }
    )
  end

  command doc: 'output the current story branch if it is checked out'
  def current(check: true)
    if check
      if cb = current_branch_checked?
        cb
      else
        error 'Switch to a story branch first for this operation!'
      end
    else
      current_branch
    end
  end

  def provide_name(story_id = nil)
    until story_id.present?
      story_id = ask(prompt: 'Story id? ').strip
    end
    story_id = story_id.gsub(/[^0-9]+/, '')
    @story_id = Integer(story_id)
    if stories.any? { |s| s.story_id == @story_id }
      @reason = "story for ##@story_id already created"
      return
    end
    if name = fetch_story_name(@story_id)
      name = normalize_name(
        name,
        max_size: 128 - 'story'.size - @story_id.to_s.size - 2 * ?_.size
      ).full? || name
      [ 'story', name, @story_id ] * ?_
    else
      @reason = "name for ##@story_id could not be fetched from tracker"
      return
    end
  end

  command doc: '[BRANCH] display build status of branch'
  def build_status(branch = current(check: false))
    auth_token = complex_config.story.semaphore_auth_token
    project    = complex_config.story.semaphore_project
    url        = "https://semaphoreci.com/api/v1/projects/#{project}/#{branch}/status?auth_token=#{auth_token}"
    Git::Story::SemaphoreResponse.get(url)
  rescue => e
    "Getting #{url.inspect} => #{e.class}: #{e}".red
  end

  command doc: '[SERVER] display deploy status of branch'
  def deploy_status(server = complex_config.story.semaphore_default_server)
    auth_token = complex_config.story.semaphore_auth_token
    project    = complex_config.story.semaphore_project
    url        = "https://semaphoreci.com/api/v1/projects/#{project}/servers/#{server}?auth_token=#{auth_token}"
    server   = Git::Story::SemaphoreResponse.get(url)
    deploys  = server.deploys
    upcoming = deploys.select(&:pending?)&.last
    current  = deploys.find(&:passed?)
    <<~end
      Server: #{server.server_name&.green}
      Branch: #{server.branch_name&.color('#ff5f00')}
      Semaphore: #{server.server_url}
      Strategy: #{server.strategy}
      Upcoming: #{upcoming}
      Current: #{current}
    end
  rescue => e
    "Getting #{url.inspect} => #{e.class}: #{e}".red
  end

  command doc: '[STORY_ID] fetch status of current story'
  def status(story_id = current(check: true)&.[](/_(\d+)\z/, 1)&.to_i)
    if story = fetch_story(story_id)
      color_state =
        case cs = story.current_state
        when 'unscheduled', 'planned', 'unstarted'
          cs
        when 'rejected'
          cs.white.on_red
        when 'accepted'
          cs.green
        else
          cs.yellow
        end
      color_type =
        case t = story.story_type
        when 'bug'
          t.red.bold
        when 'feature'
          t.yellow.bold
        when 'chore'
          t.white.bold
        else
          t
        end
      <<~end
        Id: #{(?# + story.id.to_s).green}
        Name: #{story.name.inspect.bold}
        Type: #{color_type}
        Estimate: #{story.estimate.to_s.yellow.bold}
        State: #{color_state}
        Branch: #{current_branch_checked?&.color('#ff5f00')}
        Labels: #{story.labels.map(&:name).join(' ').on_color(91)}
        Pivotal: #{story.url}
        Github: #{github_url(current_branch_checked?)}
      end
    end
  rescue => e
    "Getting pivotal story status => #{e.class}: #{e}".red
  end

  command doc: '[AUTHOR] list all stories'
  def list(author = nil, mark_red: current(check: false))
    stories.map { |b|
      next if author && !b.story_author.include?(author)
      (bn = b.story_base_name) == mark_red ? bn.red : bn.green
    }.compact
  end

  command doc: '[AUTHOR] list all stories with details'
  def list_details(author = nil, mark_red: current(check: false))
    stories.sort_by { |b| -b.story_created_at.to_f }.map { |b|
      next if author && !b.story_author.include?(author)
      name = (bn = b.story_base_name) == mark_red ? bn.red : bn.green
      "#{name} #{b.story_author} #{b.story_created_at.iso8601.yellow}"
    }.compact
  end

  command doc: 'list all production deploy tags'
  def deploy_tags
    fetch_tags
    capture(
      "git tag | grep ^#{complex_config.story.deploy_tag_prefix} | sort"
    ).lines.map(&:chomp)
  end

  command doc: 'output the times of all production deploys'
  def deploy_list
    deploy_tags.map { |t| format_tag_time(t).green + " #{t.yellow}" }
  end

  command doc: 'output the last production deploy tag'
  def deploy_tags_last
    deploy_tags.last
  end

  command doc: 'output the time of the last production deploy'
  def deploy_last
    tag = deploy_tags_last
    format_tag_time(tag).green + " #{tag.yellow}"
  end

  command doc: 'output log of changes since last production deploy tag'
  def deploy_log(ref = deploy_tags.last, last_ref = nil)
    fetch_tags
    opts = '--pretty=tformat:"%C(yellow)%h%Creset %C(green)%ci%Creset %s (%Cred%an <%ae>%Creset)"'
    capture("git log #{opts} #{ref}..#{last_ref}")
  end

  command doc: '[REF] output diff since last production deploy tag'
  def deploy_diff(ref = nil)
    fetch_tags
    opts = '-u'
    capture("git diff --color #{opts} #{ref} #{deploy_tags.last}")
  end

  command doc: '[REF] output migration diff since last production deploy tag'
  def deploy_migrate_diff(ref = nil)
    fetch_tags
    opts = '-u'
    capture("git diff --color #{opts} #{deploy_tags.last} #{ref} -- db/migrate")
  end

  command doc: '[STORYID] create a story for story STORYID'
  def create(story_id = nil)
    sh 'git fetch'
    name = provide_name(story_id) or
      error "Cannot provide a new story name for story ##{story_id}: #{@reason.inspect}"
    if old_story = stories.find { |s| s.story_id == @story_id }
      error "story ##{@story_id} already exists in #{old_story}".red
    end
    puts "Now creating story #{name.inspect}".green
    sh "git checkout --track -b #{name}"
    sh "git push -u origin #{name}"
    "Story #{name} created.".green
  end

  command doc: '[PATTERN] switch to story matching PATTERN'
  def switch(pattern = nil)
    sh 'git fetch'
    ss = stories.map(&:story_base_name)
    if pattern.present?
      b = apply_pattern(pattern, ss)
      if b.size == 1
        b = b.first
      else
        b = nil
      end
    end
    loop do
      unless b
        b = complete prompt: 'Story <TAB>? '.bright_blue do |pattern|
          apply_pattern(pattern, ss)
        end&.strip
        b.empty? and return
      end
      if branch = ss.find { |f| f == b }
        sh "git checkout #{branch}"
        return "Switched to story: #{branch}".green
      else
        b = nil
      end
    end
  rescue Interrupt
  end

  command doc: '[BRANCH] open branch on github'
  def github(branch = current(check: false))
    if url = github_url(branch)
      system "open #{url.inspect}"
    end
    nil
  end

  command doc: '[BRANCH] open branch on pivotaltracker'
  def pivotal(branch = current(check: true))
    if story_id = branch&.[](/_(\d+)\z/, 1)&.to_i
      story_url = fetch_story(story_id)&.url
      system "open #{story_url}"
    end
    nil
  end

  private

  def normalize_name(name, max_size: nil)
    name = name.downcase
    name = name.tr('äöü', 'aou').tr(?ß, 'ss')
    name = name.gsub(/[^a-z0-9-]+/, '-')
    name = name.gsub(/(\A-*|[\-0-9]*\z)/, '')
    name = name.gsub(/-+/, ?-)
    max_size and name = name[0, max_size]
    name
  end

  def apply_pattern(pattern, stories)
    pattern = pattern.gsub(?#, '')
    stories.grep(/#{Regexp.quote(pattern)}/)
  end

  def error(msg)
    puts msg.red
    exit 1
  end

  def pivotal_project
    complex_config.story.pivotal_project
  end

  def pivotal_token
    complex_config.story.pivotal_token
  end

  def fetch_story_name(story_id)
    fetch_story(story_id)&.name
  end

  def fetch_story(story_id)
    pivotal_get("projects/#{pivotal_project}/stories/#{story_id}").full?
  end

  def pivotal_get(path)
    path = path.sub(/\A\/*/, '')
    url = "https://www.pivotaltracker.com/services/v5/#{path}"
    @debug and STDERR.puts "Fetching #{url.inspect}"
    open(url,
         'X-TrackerToken' => pivotal_token,
         'Content-Type'   => 'application/xml',
    ) do |io|
      JSON.parse(io.read, object_class: JSON::GenericObject)
    end
  rescue OpenURI::HTTPError => e
    if e.message =~ /401/
      raise e.exception, "#{e.message}: API-TOKEN in env var PIVOTAL_TOKEN invalid?"
    end
  end

  memoize method:
  def fetch_tags
    sh 'git fetch --tags'
  end

  def apply_story_accessors(ref)
    branch = ref[0]
    branch =~ BRANCH_NAME_REGEX or return
    branch.extend StoryAccessors
    branch.story_base_name = ref[0]
    branch.story_name = $1
    branch.story_id = $2.to_i
    branch.story_created_at = ref[1]
    branch.story_author = ref[2]
    branch
  end

  def stories
    sh 'git remote prune origin', error: false
    refs = capture("git for-each-ref --format='%(refname);%(committerdate);%(authorname) %(authoremail)'")
    refs = refs.lines.map { |l|
      ref = l.chomp.split(?;)
      next unless ref[0] =~ %r(/origin/)
      ref[0] = File.basename(ref[0])
      next unless ref[0] =~ BRANCH_NAME_REGEX
      ref[1] = Time.parse(ref[1])
      ref
    }.compact.map do |ref|
      apply_story_accessors ref
    end.compact
  end

  def current_branch
    capture("git rev-parse --abbrev-ref HEAD").strip
  end

  def current_branch_checked?
    if (cb = current_branch) =~ BRANCH_NAME_REGEX
      cb
    end
  end

  def format_tag_time(tag)
    if tag =~ /\d{4}_\d{2}_\d{2}-\d{2}_\d{2}/
      time = Time.strptime($&, '%Y_%m_%d-%H_%M')
      day  = Time::RFC2822_DAY_NAME[time.wday]
      "#{time.iso8601} #{day}"
    end
  end

  def remote_url(name = 'origin')
    capture("git remote -v").lines.grep(/^#{name}/).first&.split(/\s+/).full?(:[], 1)
  end

  def github_url(branch)
    branch.full? or return
    url = remote_url('github') || remote_url or return
    url = url.sub('git@github.com:', 'https://github.com/')
    url = url.sub(/(\.git)\z/, "/tree/#{branch}")
  end
end
