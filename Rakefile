require 'net/http'
require 'uri'
require 'json'
require 'rake/testtask'
require_relative './lib/rubycoma'

include RubyCoMa

namespace :test do
  task(:generate_spec_tests, [:str]) { |t, args|
    line_number = 0
    start_line = 0
    end_line = 0
    example_number = 0
    markdown_lines = Array.new
    html_lines = Array.new
    state = 0  # 0 regular text, 1 markdown example, 2 html output
    header_text = ''
    tests = Array.new

    header_regex = /#+ /

    args[:str].each_line { |line|
      line_number += 1
      if state == 0 && header_regex.match(line)
        header_text = line.sub(header_regex, '').strip
      end

      if line.strip == '.'
        state = (state + 1) % 3
        if state == 0
          example_number = example_number + 1
          end_line = line_number
          tests.push({
                         :example => example_number,
                         :start_line => start_line,
                         :end_line => end_line,
                         :section => header_text,
                         :markdown => markdown_lines.join('').gsub('→',"\t"),
                         :html => html_lines.join('').gsub('→',"\t")
                     })
          start_line = 0
          markdown_lines = []
          html_lines = []
        end
      elsif state == 1
        if start_line == 0
          start_line = line_number - 1
        end
        markdown_lines.push(line)
      elsif state == 2
        html_lines.push(line)
      end
    }

    File.open('test/tests.json', 'w') { |f|
      f.write(JSON.pretty_generate(tests))
    }
  }

  task(:update_spec_tests, [:spec_path]) { |t, args|
    path = args[:spec_path] || 'https://raw.githubusercontent.com/jgm/CommonMark/master/spec.txt'
    text = Net::HTTP.get(URI.parse(path)).force_encoding('UTF-8')
    Rake::Task['test:generate_spec_tests'].invoke(text)
  }

  task(:run_spec_test, [:test_number]) { |t, args|
    abort('Didn\'t specify a test number.') if args.count < 1
    cases = JSON.parse(open('test/tests.json', 'r').read)
    obj = cases[args[:test_number].to_i-1]
    md = obj['markdown']
    parsed = Parser.new(true).parse_string(md)
    actual = HtmlRenderer.new(true).render_block(parsed)
    if actual != obj['html']
      puts "\u274c Test #{obj['example']} failed."
      print "  Input:     "
      p obj['markdown']
      print "  Output:    "
      p actual
      print "  Expected:  "
      p obj['html']
    else
      puts "\u2705 Test #{obj['example']} passed."
    end
  }

  task(:run_spec_tests) { |t|
    cases = JSON.parse(open('test/tests.json', 'r').read)

    cases.each { |obj|
      md = obj['markdown']
      parsed = Parser.new.parse_string(md)
      actual = HtmlRenderer.new.render_block(parsed)
      if actual != obj['html']
        puts "\u274c Test #{obj['example']} failed."
        # print "  Input:     "
        # p obj['markdown']
        # print "  Output:    "
        # p actual
        # print "  Expected:  "
        # p obj['html']
      else
        puts "\u2705 Test #{obj['example']} passed."
      end
    }
  }
end
