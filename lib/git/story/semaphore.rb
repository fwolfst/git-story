require 'json'
require 'time'
require 'open-uri'
require 'infobar'

class Git::Story::SemaphoreResponse < JSON::GenericObject
  def self.get(url, debug: false)
    data = URI.open(url).read
    debug and STDERR.puts JSON.pretty_generate(JSON(data))
    result = JSON(data, object_class: self)
    result.debug = debug
    result
  end

  def duration(time = nil)
    unless time
      if finished_at.nil?
        time = Time.now
      else
        time = Time.parse(finished_at)
      end
    end
    if started_at
      Tins::Duration.new(time - Time.parse(started_at))
    else
      Tins::Duration.new(0)
    end
  end

  def pending?
    result == 'pending'
  end

  def building?
    !started_at.nil?
  end

  def passed?
    result == 'passed'
  end

  def failed?
    result == 'failed'
  end

  def canceled?
    result == 'canceled'
  end

  def finished?
    finished_at.blank?
  end

  def sha1
    commit.id[0,10]
  end

  def entity_url
    server_html_url || build_url
  end

  def entity_name
    branch_name || server_name
  end

  def branch_history
    if branch_history_url
      self.class.get(branch_history_url, debug: debug)&.builds
    else
      []
    end
  end

  def estimated_duration
    if ed = super
      ed
    else
      times = branch_history.select(&:passed?).map { |b|
        Time.parse(b.finished_at) - Time.parse(b.started_at)
      }
      if times.empty?
        duration
      else
        times.sum / times.size
      end.to_f
    end
  end

  def infobar_style
    case
    when passed?, pending?
      {
        done_fg_color: '#005f00',
        done_bg_color: '#00d700',
        todo_fg_color: '#00d700',
        todo_bg_color: '#005f00',
      }
    else
      {
        done_fg_color: '#5f0000',
        done_bg_color: '#d70000',
        todo_fg_color: '#d70000',
        todo_bg_color: '#5f0000',
      }
    end
  end

  def to_s
    r = case
        when pending? && building?
          "#{entity_name} ##{sha1} building for #{duration(Time.now)}".yellow.bold
        when pending?
          "#{entity_name} ##{sha1} pending at the moment".yellow
        when passed?
          "#{entity_name} ##{sha1} passed after #{duration}".green
        when failed?
          "#{entity_name} ##{sha1} failed after #{duration}".red
        else
          "#{entity_name} ##{sha1} in state #{result}".blue
        end
    r = StringIO.new(r)
    duration_seconds = duration.to_f.to_i
    if passed? || failed?
      total_seconds = duration_seconds
    else
      total_seconds = estimated_duration.to_i
    end
    Infobar(
      current: duration_seconds,
      total: total_seconds,
      message: ' %l %c/%t seconds ',
      style: infobar_style,
      output: r
    ).update
    r <<
      "\n  Semaphore: #{entity_url}" <<
      "\n  Commit: #{commit.url}\n#{commit.message&.gsub(/^/, " " * 10)&.color(33)}" <<
      "\n  Authored: #{(commit.author_name + ' <' + commit.author_email + ?>).bold} @#{commit.timestamp}"
    r.tap(&:rewind).read
  end
end
