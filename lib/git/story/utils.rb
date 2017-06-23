require 'fileutils'

module Git::Story::Utils
  include FileUtils::Verbose

  def sh(*a, error: true)
    system(*a)
    if error && !$?.success?
      STDERR.puts ("Failed with rc #{$?.exitstatus}: " + a.join(' ')).red
      exit $?.exitstatus
    end
  end

  def ask(prompt: '? ', **options, &block)
    response = options[:preset]
    unless response
      if options[:default]
        $stdout.print prompt % options[:default]
        response = $stdin.gets.chomp
        response.empty? and response = options[:default]
      else
        $stdout.print prompt
        response = $stdin.gets
      end
    end
    response = response.to_s.chomp
    if block
      block.(response)
    else
      response
    end
  end
end
