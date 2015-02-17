module RubyCoMa
  require_relative './rubycoma/parser'

  def parse_file(filename)
    Parser.new.parse_file(filename)
  end
end