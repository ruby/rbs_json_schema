require "optparse"

module RBSJsonSchema
  class CLI
    attr_reader :stdout
    attr_reader :stderr

    def initialize(stdout:, stderr:)
      @stdout = stdout
      @stderr = stderr
      @options = {}
    end

    def run(args)
      OptionParser.new do |opts|
        opts.banner = <<~USAGE
        Usage: rbs_json_schema [options...] [path...]

        Generates RBS files from JSON Schema.

        Options:
        USAGE

        opts.on("--[no-]stringify-keys", "Generate record types with string keys") do |bool|
          @options[:stringify_keys] = bool
        end

        opts.on("-o OUTPUT", "Output the generated RBS to a specific location") do |location|
          @options[:output] = location
        end
      end.parse!(args)

      generator = Generator.new(stringify_keys: @options[:stringify_keys], output: @options[:output], stdout: stdout, stderr: stderr)
      args.each do |path|
        path =
          begin
            Pathname(path).realpath
          rescue Errno::ENOENT => _
            raise ValidationError.new(message: "#{path}: No such file or directory found!")
          end

        case
        when path.file?
          generator.generate(URI.parse("file://#{path}"))
        when path.directory?
          Dir["#{path}/*.{json}"].sort.each do |file|
            file = Pathname(file).realpath
            generator.generate(URI.parse("file://#{file}"))
          end
        else
          raise ValidationError.new(message: "#{path}: No such file or directory found!")
        end
      end
      generator.write_output
    end
  end
end
