require 'time'
require 'open-uri'
require 'tins/go'
require 'set'
require 'infobar'
require 'search_ui'
require 'amatch'

class Git::Story::App
  class ::String
    include Term::ANSIColor
  end

  include Git::Story::Utils
  extend Git::Story::Utils
  include ComplexConfig::Provider::Shortcuts
  include Tins::GO
  include SearchUI

  annotate :command

  BRANCH_NAME_REGEX = /\A(story|feature)_([a-z0-9-]+)_(\d+)\z/

  module StoryAccessors
    attr_accessor :story_name

    attr_accessor :story_base_name

    attr_accessor :story_id

    attr_accessor :story_created_at

    attr_accessor :story_author
  end

  def initialize(argv = ARGV.dup, debug: ENV['DEBUG'].to_i == 1)
    @rest_argv = (sep = argv.index('--')) ? argv.slice!(sep..-1).tap(&:shift) : []
    @argv      = argv
    @opts      = go 'n:', @argv
    @debug     = debug
    determine_command
    Git::Story::Setup.perform
  end

  def run
    if command_of(@command)
      if method(@command).parameters.include?(%i[key rest])
        puts __send__(@command, *@argv, rest: @rest_argv)
      else
        puts __send__(@command, *@argv)
      end
    else
      if @command
        @command = @command.inspect
      else
        @command = 'n/a'
      end
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
        "#{name.to_s.gsub(?_, ' ').ljust(longest)} #{a[:doc]}"
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

  command doc: '[STORY_ID] fetch status of current story, -n SECONDS refreshes'
  def status(story_id = current(check: true)&.[](/_(\d+)\z/, 1)&.to_i)
    if story = fetch_story(story_id)
      color_state =
        case cs = story.current_state
        when 'unscheduled', 'planned', 'unstarted'
          cs
        when 'rejected'
          cs.white.on_red
        when 'accepted'
          cs.black.on_green
        else
          cs.black.on_yellow
        end.italic
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
      owners = Array(fetch_story_owners(story_id)).map { |o| "#{o.name} <#{o.email}>" }
      result = <<~end
        Id: #{(?# + story.id.to_s).green}
        Name: #{story.name.inspect.bold}
        Type: #{color_type}
        Estimate: #{story.estimate.to_s.full? { |e| e.yellow.bold } || 'n/a'}
        State: #{color_state}
        Branch: #{current_branch_checked?&.color('#ff5f00')}
        Labels: #{story.labels.map { |l| l.name.on_color(91) }.join(' ')}
        Owners: #{owners.join(', ').yellow}
        Pivotal: #{story.url.color(33)}
      end
      if url = github_url(current_branch_checked?)
        result << "Github: #{url.color(33)}\n"
      end
      result
    end
  rescue => e
    "Getting pivotal story status => #{e.class}: #{e}\n#{e.backtrace.join(?n)}".red
  end

  command doc: '[AUTHOR] list all stories'
  def list(author = nil, mark_red: current(check: false))
    stories.map { |b|
      next if author && !b.story_author.include?(author)
      (bn = b.story_base_name) == mark_red ? bn.red : bn.green
    }.compact
  end

  command doc: '[AUTHOR] list all stories with details'
  def details(author = nil, mark_red: current(check: false))
    stories.sort_by { |b| -b.story_created_at.to_f }.map { |b|
      next if author && !b.story_author.include?(author)
      name = (bn = b.story_base_name) == mark_red ? bn.red : bn.green
      "#{name} #{b.story_author} #{b.story_created_at.iso8601.yellow}"
    }.compact
  end
  alias list_details details

  command doc: 'list all production deploy tags'
  def deploy_tags
    tags.map { |t| tag_name(t) }
  end

  command doc: 'output the times of all production deploys'
  def deploys
    tags.map { |t| format_tag(t) }
  end
  alias deploy_list deploys

  command doc: 'output the last production deploy tag'
  def deploy_tags_last
    tag_name(tags.last)
  end

  command doc: 'output the time of the last production deploy'
  def deploy_last
    format_tag(tags.last)
  end

  command doc: '[REF] output log of changes since last production deploy tag'
  def deploy_log(ref = default_ref, rest: [])
    ref = build_ref_range(ref)
    fetch_commits
    fetch_tags
    opts = ([
      '--color',
      '--pretty=tformat:"%C(yellow)%h%Creset %C(green)%ci%Creset %s (%Cred%an <%ae>%Creset)"'
    ] | rest) * ' '
    capture("git log #{opts} #{ref}")
  end

  command doc: '[REF] List all stories scheduled for next deploy'
  def deploy_stories(ref = default_ref, rest: [])
    ref = build_ref_range(ref)
    fetch_commits
    fetch_tags
    opts = ([
      '--color=never',
      '--pretty=%B'
    ] | rest) * ' '
    output = capture("git log #{opts} #{ref}")
    pivotal_ids = SortedSet[]
    output.scan(/\[\s*#\s*(\d+)\s*\]/) { pivotal_ids << $1.to_i }
    fetch_statuses(pivotal_ids) * (?┄ * Tins::Terminal.cols << ?\n)
  end

  def fetch_statuses(pivotal_ids)
    tg = ThreadGroup.new
    pivotal_ids.each do |pid|
      tg.add Thread.new { Thread.current[:status] = status(pid) }
    end
    tg.list.with_infobar(label: 'Story').map do |t|
      +infobar
      t.join
      t[:status]
    end
  end

  command doc: '[REF] output diff since last production deploy tag'
  def deploy_diff(ref = default_ref, rest: [])
    ref = build_ref_range(ref)
    fetch_commits
    opts = (%w[ --color -u ] | rest) * ' '
    capture("git diff #{opts} #{ref}")
  end

  command doc: '[REF] output migration diff since last production deploy tag'
  def deploy_migrate_diff(ref = default_ref, rest: [])
    ref = build_ref_range(ref)
    fetch_commits
    opts = (%w[ --color -u ] | rest) * ' '
    capture("git diff #{opts} #{ref} -- db/migrate")
  end

  command doc: '[STORYID] create a story for story STORYID'
  def create(story_id = nil)
    fetch_commits
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
    fetch_commits
    if branch = pick_branch(prompt: 'Switch to story? %s')
      sh "git checkout #{branch}"
      return "Switched to story: #{branch}".green
    end
  end

  command doc: '[PATTERN] delete story branch matching PATTERN'
  def delete(pattern = nil)
    fetch_commits
    if branch = pick_branch(prompt: 'Delete story branch? %s', symbol: ?⌦)
      sh "git pull origin #{branch}"
      sh "git branch -d #{branch}"
      if ask(prompt: 'Delete remote branch? (y/N) ') =~ /\Ay\z/i
        sh "git push origin #{branch} --delete"
      end
      return "Deleted story branch: #{branch}".green
    end
  end

  command doc: '[BRANCH] open branch on github'
  def github(branch = current(check: false))
    if url = github_url(branch)
      sh "open #{url.inspect}"
    end
    nil
  end

  command doc: '[BRANCH] open branch on pivotaltracker'
  def pivotal(branch = current(check: true))
    if story_id = branch&.[](/_(\d+)\z/, 1)&.to_i
      story_url = fetch_story(story_id)&.url
      sh "open #{story_url}"
    end
    nil
  end

  command doc: 'open project on semaphore'
  def semaphore
    sh "open #{complex_config.story.semaphore_project_url}"
    nil
  end

  command doc: '[REF] create a hotfix branch from REF'
  def hotfix(ref = nil)
    if ref
      start_point = ref
    elsif tag = tags.last
      start_point = tag_name(tag)
    else
      fail 'no last deployment tag found'
    end
    branch = "hotfix_#{start_point}"
    sh "git checkout -b #{branch.inspect} #{start_point.inspect}"
    nil
  end

  private

  def determine_command
    c, command = [], nil
    possible_commands = []
    until @argv.empty?
      c << @argv.shift
      command = c.join(?_).to_sym
      if command_of(command)
        possible_commands << [ command, @argv.dup ]
      end
    end
    unless possible_commands.empty?
      @command, argv = possible_commands.last
      @argv.replace(argv)
    end
    self
  end

  def pick_branch(prompt:, symbol: ?⏻)
    ss = stories.map(&:story_base_name)
    branch = Search.new(
      match: -> answer {
        answer = answer.strip.delete(?#).downcase

        matcher = Amatch::PairDistance.new(answer)
        matches = ss.map { |n| [ n, -matcher.similar(n.downcase) ] }.
          select { |_, s| s < 0 }.sort_by(&:last).map(&:first)

        matches.empty? and matches = ss
        matches.first(Tins::Terminal.lines - 1)
      },
      query: -> _answer, matches, selector {
        matches.each_with_index.
          map { |m, i| i == selector ? "#{symbol} " + Search.on_blue(m) : '┊ ' + m } * ?\n
      },
      found: -> _answer, matches, selector {
        matches[selector]
      },
      prompt: prompt.bold,
      output: STDOUT
    ).start
  end

  def default_ref
    tags.last
  end

  def build_ref_range(ref)
    ref = tag_name(ref)
    if 'previous' == ref and (previous = tags.last(2)).size == 2
      previous.map { |t| tag_name(t) } * '..'
    elsif /^(?<before>.+?)?\.\.(?<after>.+)?\z/ =~ ref
      if before && after
        "#{before}..#{after}"
      elsif !before
        "#{default_ref}..#{after}"
      elsif !after
        "#{before}.."
      else
        "#{default_ref}.."
      end
    else
      "#{ref}.."
    end
  end

  def tags
    capture(deploy_tag_command).lines.map(&:chomp)
  end

  def deploy_tag_command
    fetch_tags
    if command = complex_config.story.deploy_tag_command?
      command
    else
      "git tag | grep ^#{complex_config.story.deploy_tag_prefix} | sort"
    end
  end

  def watch(&block)
    if seconds = @opts[?n]&.to_i and !@watching
      @watching = true
      if seconds == 0
        seconds = 60
      end
      loop do
        r = block.()
        sh 'clear'
        start = Time.now
        puts r
        refresh_at = start + seconds
        duration = refresh_at - start
        if duration > 0
          puts "<<< #{Time.now.iso8601} Refresh every #{seconds} seconds >>>".rjust(Tins::Terminal.cols)
          sleep duration
        end
      end
    else
      block.()
    end
  end

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

  def fetch_story_owners(story_id)
    pivotal_get("projects/#{pivotal_project}/stories/#{story_id}/owners")
  end

  def pivotal_get(path)
    path = path.sub(/\A\/*/, '')
    url = "https://www.pivotaltracker.com/services/v5/#{path}"
    if pivotal_token
      @debug and STDERR.puts "Fetching #{url.inspect}"
    else
      STDERR.puts "Cannot fetch #{url.inspect} without PIVOTAL_TOKEN set as env var"
      return
    end
    URI.open(url,
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

  memoize method:
  def fetch_commits
    sh 'git fetch'
  end

  def apply_story_accessors(ref)
    branch = ref[0]
    branch =~ BRANCH_NAME_REGEX or return
    branch.extend StoryAccessors
    branch.story_base_name = "#$1_#$2_#$3"
    branch.story_name = $2
    branch.story_id = $3.to_i
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

  def tag_time(tag)
    case tag
    when %r(\A\d{4}/\d{2}/\d{2}\d{2}:\d{2}:\d{2} (\S+))
      return Time.strptime($&, '%Y/%m/%d%H:%M'), $1
    when /\d{4}_\d{2}_\d{2}-\d{2}_\d{2}\z/
      return Time.strptime($&, '%Y_%m_%d-%H_%M'), tag
    else
      return nil, tag
    end
  end

  def tag_name(tag)
    tag_time(tag)&.last
  end

  def format_tag(tag)
    time, tag_name = tag_time(tag)
    if time
      day  = Time::RFC2822_DAY_NAME[time.wday]
      "%s %s %s %s" % [
        time.iso8601.green,
        day.green,
        tag_name.to_s.yellow,
        "was #{Tins::Duration.new((Time.now - time).floor)} ago".green,
      ]
    else
      tag_name
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
