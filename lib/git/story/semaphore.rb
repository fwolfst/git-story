require 'json'
require 'time'
require 'open-uri'
require 'infobar'

class Git::Story::SemaphoreResponse < JSON::GenericObject
  def self.get(url, debug: false)
    data = open(url).read
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
    Tins::Duration.new(time - Time.parse(started_at))
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
    times = branch_history.select { |b| b.result == 'passed' }.map { |b|
      Time.parse(b.finished_at) - Time.parse(b.started_at)
    }
    if times.empty?
      duration
    else
      times.sum / times.size
    end.to_f
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
    Infobar(
      current: duration.to_f.to_i,
      total: estimated_duration.to_i,
      message: ' %l %c/%t seconds ',
      output: r
    ).update
    r <<
      "\n  Semaphore: #{entity_url}" <<
      "\n  Commit: #{commit.url}" <<
      "\n  Authored: #{(commit.author_name + ' <' + commit.author_email + ?>).bold} @#{commit.timestamp}"
    r.tap(&:rewind).read
  end
end
