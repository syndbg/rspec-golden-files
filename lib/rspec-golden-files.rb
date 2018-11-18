# frozen_string_literal: true

require 'tempfile'
require 'erb'
require 'ostruct'

module RSpec
  module GoldenFiles
    VERSION = '0.1.1'.freeze

    class SimpleFileReader
      def initialize(filename)
        @filename = filename
        @file_contents = File.read(@filename)
      end

      def filename
        @filename
      end

      def expected_value
        @file_contents
      end

      def close; end
    end

    class ErbFileReader < SimpleFileReader
      # HACK: Make hash keys usable in templates
      # due to ERB's poor `#result_with_hash` usefulness.
      class TemplateStruct < OpenStruct
        def render(template)
          template.result(binding)
        end
      end

      def initialize(filename, template_vars)
        plain_file_contents = File.read(filename)
        template = ERB.new(plain_file_contents)
        template_struct = TemplateStruct.new(template_vars)

        @file_contents = template_struct.render(template)

        @tmpfile = Tempfile.new('expected')
        @tmpfile.write(@file_contents)
        @tmpfile.close(false)

        @filename = @tmpfile.path
      end

      def close
        @tmpfile.delete
      end
    end

    class GoldenFilesMatcher
      def initialize(filename, file_reader_type, template_vars)
        @filename = filename
        @file_reader_type = file_reader_type
        @template_vars = template_vars
      end

      def matches?(value)
        unless File.exist?(@filename)
          raise ArgumentError "golden file '#{@filename}' not found"
        end

        @value = value

        actual_tmpfile = Tempfile.new('actual')
        actual_tmpfile.write(value.to_s)
        actual_tmpfile.close(false)

        file_reader = case @file_reader_type.to_sym
                      when :simple
                        SimpleFileReader.new(@filename)
                      when :erb
                        ErbFileReader.new(@filename, @template_vars)
                      else
                        raise ArgumentError "unknown file reader type #{@file_reader_type}. `simple` and `erb` are supported"
                      end

        @expected_value = file_reader.expected_value
        system("diff #{actual_tmpfile.path} #{file_reader.filename} > /dev/null")
        is_successful = $CHILD_STATUS.to_i.zero?

        file_reader.close
        actual_tmpfile.delete

        is_successful
      end

      def actual
        @value
      end

      def expected
        @expected_value
      end

      def description
        "be matching golden file with name #{@filename}"
      end

      def diffable?
        true
      end

      def failure_message
        "expected #{@value.inspect} does not match golden file '#{@filename}'"
      end

      def failure_message_when_negated
        "expected #{@value.inspect} matches golden file '#{@filename}'"
      end
    end
  end

  def match_golden_file(filename, file_reader_type: 'simple', template_vars: {})
    RSpec::Matchers::GoldenFiles::GoldenFilesMatcher.new(filename, file_reader_type, template_vars)
  end
end
