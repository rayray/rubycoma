module RubyCoMa
  require_relative './rubycoma/parser'
  require_relative './rubycoma/html_renderer'

  def parse_file(filename)
    Parser.new.parse_file(filename)
  end
end