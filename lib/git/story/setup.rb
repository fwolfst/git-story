module Git::Story::Setup
  include Git::Story::Utils
  extend Git::Story::Utils

  MARKER = 'Installed by the git-story gem'

  HOOKS_DIR = '.git/hooks'
  PREPARE_COMMIT_MESSAGE_SRC = File.join(__dir__, 'prepare-commit-msg')
  PREPARE_COMMIT_MESSAGE_DST = File.join(HOOKS_DIR, 'prepare-commit-msg')

  module_function

  def perform(force: false)
    for filename in %w[ prepare-commit-msg pre-push ]
      if path = file_installed?(filename)
        if force
          install_file filename
        elsif File.read(path).match?(MARKER)
          ;
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
    cp File.join(__dir__, filename), File.join(HOOKS_DIR, filename)
  end
end
