module Git::Story::Setup
  include Git::Story::Utils
  extend Git::Story::Utils

  MARKER = 'Installed by the git-story gem'

  PREPARE_COMMIT_MESSAGE_SRC =
    File.join(File.dirname(__FILE__), 'prepare-commit-msg')
  PREPARE_COMMIT_MESSAGE_DST =
    '.git/hooks/prepare-commit-msg'

  module_function

  def perform(force: false)
    pcm = '.git/hooks/prepare-commit-msg'
    if File.exist?(pcm)
      if force
        install_prepare_commit_msg
      elsif File.read(pcm).match?(MARKER)
        ;
      else
        ask(
          prompt: "File #{pcm.inspect} not created by git-story."\
            " Overwrite? (y/n, default is %s)",
          default: ?n,
        ) do |response|
          if response == ?y
            install_prepare_commit_msg
          end
        end
      end
    else
      install_prepare_commit_msg
    end
  end

  def install_prepare_commit_msg
    cp PREPARE_COMMIT_MESSAGE_SRC, PREPARE_COMMIT_MESSAGE_DST
  end
end
