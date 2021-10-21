module Git::Story::Setup
  include Git::Story::Utils
  extend Git::Story::Utils

  MARKER = 'Installed by the git-story gem'

  HOOKS_DIR = '.git/hooks'
  PREPARE_COMMIT_MESSAGE_SRC = File.join(__dir__, 'prepare-commit-msg')
  PREPARE_COMMIT_MESSAGE_DST = File.join(HOOKS_DIR, 'prepare-commit-msg')

  CONFIG_TEMPLATE = <<~end
    ---
    pivotal_token:   <%= ENV['PIVOTAL_TOKEN'] %>
    pivotal_project: 123456789
    pivotal_reference_prefix: pivotal
    deploy_tag_prefix: production_deploy_
    semaphore_auth_token: <%= ENV['SEMAPHORE_AUTH_TOKEN'] %>
    semaphore_project_url: https://betterplace.semaphoreci.com/projects/betterplace
    todo_nudging: <%= ENV['TODO_NUDGING'].to_i == 1 %>
  end


  module_function

  def perform(force: false)
    unless File.directory?('.git')
      puts "No directory .git found, you need an initialized git repo for this to work"
      return
    end
    install_config('config/story.yml', force: force)
    install_hooks(force: force)
    "Setup was performed."
  end

  def install_hooks(force: false)
    for filename in %w[ prepare-commit-msg pre-push ]
      if path = file_installed?(filename)
        if force || File.read(path).match?(MARKER)
          install_file filename
        else
          ask(
            prompt: "File #{path.inspect} not created by git-story."\
              " Overwrite? (y/n, default is %s) ",
            default: ?n,
          ) do |response|
            if response == ?y
              install_file filename
            end
          end
        end
      else
        install_file filename
      end
    end
  end

  def file_installed?(filename)
    path = File.join(HOOKS_DIR, filename)
    if File.exist?(path)
      path
    end
  end

  def install_file(filename)
    File.exist?(HOOKS_DIR) or mkdir_p(HOOKS_DIR)
    cp File.join(__dir__, filename), dest = File.join(HOOKS_DIR, filename)
    puts "#{filename.to_s.inspect} was installed to #{dest.to_s.inspect}."
  end

  def install_config(filename, force: false)
    filename = File.expand_path(filename)
    if !force && File.exist?(filename)
      ask(
        prompt: "File #{filename.to_s.inspect} exists."\
        " Overwrite? (y/n, default is %s) ",
        default: ?n,
      ) do |response|
        if response != ?y
          puts "Skipping creation of #{filename.to_s.inspect}."
          return
        end
      end
    end
    mkdir_p File.dirname(filename)
    File.secure_write(filename) do |io|
      io.puts CONFIG_TEMPLATE
    end
    puts "#{filename.to_s.inspect} was created."
  end
end
