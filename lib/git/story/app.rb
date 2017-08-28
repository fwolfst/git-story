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
    check and check_current
    current_branch
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
      name = name.downcase.gsub(/[^a-z0-9-]+/, '-').gsub(/(\A-*|[\-0-9]*\z)/, '')
      [ 'story', name, @story_id ] * ?_
    else
      @reason = "name for ##@story_id could not be fetched from tracker"
      return
    end
  end

  command doc: 'list all stories'
  def list(mark_red: current(check: false))
    stories.map { |b|
      (bn = b.story_base_name) == mark_red ? bn.red : bn.green
    }
  end

  command doc: 'list all production deploy tags'
  def deploy_tags
    fetch_tags
    capture(
      "git tag | grep ^#{complex_config.story.deploy_tag_prefix} | sort"
    ).lines.map(&:chomp)
  end

  command doc: 'output the times of all production deploys'
  def deploys
    deploy_tags.map { |t| format_tag_time(t).green + " #{t.yellow}" }
  end

  command doc: 'output the last production deploy tag'
  def deploy_tags_last
    deploy_tags.last
  end

  command doc: 'output the time of the last production deploy'
  def deploys_last
    tag = deploy_tags_last
    format_tag_time(tag).green + " #{tag.yellow}"
  end

  command doc: 'output log of changes since last production deploy tag'
  def deploy_log
    fetch_tags
    opts = '--pretty=tformat:"%C(yellow)%h%Creset %C(green)%ci%Creset %s (%Cred%an <%ae>%Creset)"'
    capture("git log #{opts} #{deploy_tags.last}..")
  end

  command doc: 'output diff since last production deploy tag'
  def deploy_diff(ref = nil)
    fetch_tags
    opts = '-u'
    capture("git diff --color #{opts} #{ref} #{deploy_tags.last}")
  end

  command doc: 'output migration diff since last production deploy tag'
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

  private

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
    if story = pivotal_get("projects/#{pivotal_project}/stories/#{story_id}")
      story_name = story.name.full? or return
    end
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

  def fetch_tags
    sh 'git fetch --tags'
  end

  def stories
    sh 'git remote prune origin', error: false
    capture("git branch -r | grep -e '^ *origin/'").lines.map do |l|
      b = l.strip
      b_base = File.basename(b)
      if b_base =~ BRANCH_NAME_REGEX
        b.extend StoryAccessors
        b.story_base_name = b_base
        b.story_name = $1
        b.story_id = $2.to_i
        b
      end
    end.compact
  end

  def current_branch
    capture("git rev-parse --abbrev-ref HEAD").strip
  end

  def check_current
    current_branch =~ BRANCH_NAME_REGEX or
      error 'Switch to a story branch first for this operation!'
  end

  def format_tag_time(tag)
    if tag =~ /\d{4}_\d{2}_\d{2}-\d{2}_\d{2}/
      time = Time.strptime($&, '%Y_%m_%d-%H_%M')
      day  = Time::RFC2822_DAY_NAME[time.wday]
      "#{time.iso8601} #{day}"
    end
  end
end
