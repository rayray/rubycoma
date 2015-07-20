module Nodes

  class DLLNode
    attr_accessor :next
    attr_accessor :prev
    attr_accessor :first_child
    attr_accessor :last_child
    attr_accessor :parent

    def initialize
      @prev = nil
      @next = nil
      @parent = nil
      @first_child = nil
      @last_child = nil
    end

    def remove
      unless @prev.nil?
        @prev.next = @next
      end

      unless @next.nil?
        @next.prev = @prev
      end

      @prev, @next = nil, nil
    end

    def insert(node)
      unless @next.nil?
        @next.prev = node
        node.next = @next
      end

      @next = node
      node.prev = self
    end

    def add_child(child)
      child.parent = self

      if @last_child.nil?
        @first_child = child
      else
        @last_child.insert(child)
      end

      @last_child = child
    end

    def remove_child(child)
      if child == @first_child
        @first_child = child.next
      end

      if child == @last_child
        @last_child = @last_child.prev
      end
      child.parent = nil
      child.remove
    end
  end

  class Inline < DLLNode
    :text
    :normal
    :emphasized
    :strong
    :strikethrough
    :code_inline
    :link
    :image
    :softbreak
    :hardbreak
    :html_inline

    attr_accessor :style
    attr_accessor :content

    attr_accessor :destination
    attr_accessor :title

    def initialize(style, content = nil)
      super()
      @style = style
      @content = content
      @attributes = Hash.new
      @parent = nil
    end

    def is_container?
      @style == :strong || @style == :emphasized || @style == :link || @style == :image
    end

    def to_s(indent = 0)
      var_indent = indent + 2
      arr_indent = indent + 4
      str =  ' ' * indent << "{\n"

      str << ' ' * var_indent << "style: #{@style}\n"

      self.instance_variables.each { |var|
        if var == :@parent || var == :@next || var == :@prev || var  == :@last_child || var == :@style
          next
        end
        value = instance_variable_get(var)

        if var == :@first_child
          next if value.nil?
          str << ' ' * var_indent << "children: [\n"
          current = value
          until current.nil?
            str << current.to_s(arr_indent)
            current = current.next
          end
          str << ' ' * var_indent << "]\n"
        elsif value.class == Array && value.count > 0
          str << ' ' * var_indent << "#{var}: [\n"
          value.each { |obj|
            if obj.class == String
              str << ' ' * arr_indent << "\"#{obj.to_s}\"\n"
            end
          }
          str << ' ' * var_indent << "]\n"
        else
          str << ' ' * var_indent << "#{var}: #{value}\n"
        end
      }

      str << ' ' * indent << "}\n"
      str
    end
  end

  class Block < DLLNode
    attr_accessor :parent
    attr_accessor :open

    def initialize
      super()
      @open = true
    end

    def type
      self.class.name
    end

    def to_s(indent = 0)
      var_indent = indent + 2
      arr_indent = indent + 4
      str =  ' ' * indent << "{\n"
      str << ' ' * var_indent << "class: " << self.class.name << "\n"

      self.instance_variables.each { |var|
        if var == :@parent || var == :@next || var == :@prev || var  == :@last_child
          next
        end
        value = instance_variable_get(var)

        if var == :@first_child
          next if value.nil?
          str << ' ' * var_indent << "children: [\n"
          current = value
          until current.nil?
            str << current.to_s(arr_indent)
            current = current.next
          end
          str << ' ' * var_indent << "]\n"
        elsif value.class == Array && value.count > 0
          str << ' ' * var_indent << "#{var}: [\n"
          value.each { |obj|
            if obj.class == String
              str << ' ' * arr_indent << "\"#{obj.to_s}\"\n"
            end
          }
          str << ' ' * var_indent << "]\n"
        else
          str << ' ' * var_indent << "#{var}: #{value}\n"
        end
      }

      str << ' ' * indent << "}\n"
      str
    end

    def accepts_lines?
      false
    end

    def can_contain?(block)
      false
    end

  end

  class Leaf < Block
    attr_accessor :strings

    def initialize
      super()
      @strings = Array.new
    end

    def accepts_lines?
      true
    end

    def can_contain?(block)
      false
    end
  end

  class Paragraph < Leaf; end
  class HTML < Leaf; end
  class Code < Leaf
    attr_accessor :is_fenced
    attr_accessor :fence_character
    attr_accessor :fence_length
    attr_accessor :fence_offset
    attr_accessor :info_string

    def initialize(fenced = false, char = nil, length = nil, offset = nil)
      super()
      @is_fenced = fenced
      if char && length && offset
        @fence_character, @fence_length, @fence_offset = char, length, offset
      end
    end
  end

  class HorizontalRule < Leaf; def accepts_lines?; false; end; end
  class Header < Leaf
    attr_accessor :level
    def initialize(l)
      super()
      @level = l
    end
    def accepts_lines?; false; end
  end


  class Container < Block
    def initialize
      super()
    end

    def can_contain?(block)
      block.class != ListItem
    end

    def is_container?
      true
    end
  end

  class Document < Container; end
  class BlockQuote < Container; end

  class List < Container
    attr_accessor :is_ordered
    attr_accessor :is_tight
    attr_accessor :marker_character
    attr_accessor :start
    attr_accessor :delimiter
    attr_accessor :marker_offset
    attr_accessor :padding

    def can_contain?(block); block.class == ListItem; end
    def initialize(ordered)
      super()
      @is_tight = true
      @is_ordered = ordered
    end

    def matches?(l)
      @is_ordered == l.is_ordered && @delimiter == l.delimiter && @marker_character == l.marker_character
    end

    def copy_properties(l)
      @is_ordered = l.is_ordered
      @is_tight = l.is_tight
      @marker_character = l.marker_character
      @start = l.start
      @delimiter = l.delimiter
      @marker_offset = l.marker_offset
      @padding = l.padding
    end
  end

  #inheritance abuse!
  class ListItem < List
    def can_contain?(block)
      block.class != ListItem
    end
  end

  class NodeWalker
    attr_accessor :root
    attr_accessor :current
    attr_accessor :entering

    def initialize(node)
      @root = node
      @current = node
      @entering = true
    end

    def next
      return nil if @current.nil?

      cur = @current

      is_container = (@current.class < Container || (@current.class < Inline && @current.is_container?))

      if @entering && is_container
        if cur.first_child
          @current = cur.first_child
          @entering = true
        else
          @entering = false
        end
      elsif cur == @root
        @current = nil
      elsif cur.next.nil?
        @current = cur.parent
        @entering = false
      else
        @current = cur.next
        @entering = true
      end

      cur
    end

  end
end
