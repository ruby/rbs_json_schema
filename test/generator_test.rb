require "test_helper"

class GeneratorTest < Minitest::Test
  include TestHelper

  include RBSJsonSchema

  def output
    @output ||= ""
  end

  def stdout
    @stdout ||= StringIO.new
  end

  def stderr
    @stderr ||= StringIO.new
  end

  def generator
    @generator ||= Generator.new(
      stringify_keys: false,
      output: output,
      stdout: stdout,
      stderr: stderr
    )
  end

  def in_tmpdir
    Dir.mktmpdir() do |dir|
      Dir.chdir(dir) do
        yield Pathname(dir)
      end
    end
  end

  def test_read_from_uri_nil
    in_tmpdir do |path|
      path.join("foo.json").write(<<-JSON)
{}
      JSON

      assert_equal({}, generator.read_from_uri(URI.parse("foo.json")))
      assert_equal({}, generator.read_from_uri(URI.parse("./foo.json")))
    end
  end

  def test_read_from_uri_file
    in_tmpdir do |path|
      path.join("foo.json").write(<<-JSON)
{}
      JSON

      assert_equal({}, generator.read_from_uri(URI.parse("file://#{path}/foo.json")))
    end
  end

  def test_read_from_uri_with_fragment
    in_tmpdir do |path|
      path.join("foo.json").write(<<-JSON)
{
  "$defs": {
    "bar": [1,2,3]
  }
}
      JSON

      assert_equal([1,2,3], generator.read_from_uri(URI.parse("file://#{path}/foo.json#/$defs/bar")))
    end
  end
end
