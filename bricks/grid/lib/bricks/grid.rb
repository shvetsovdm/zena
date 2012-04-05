# encoding: utf-8
require 'json'

module Bricks
  module Grid
    module Common

      # Build a tabular content from a node's attribute
      def get_table_from_json(text)
        if text.blank?
          table = [{"type"=>"table"},[["[title]"],["value"]]]
        else
          table = JSON.parse(text)
        end

        raise JSON::ParserError unless table.kind_of?(Array) && table.size == 2 && table[0].kind_of?(Hash) && table[0]['type'] == 'table' && table[1].kind_of?(Array)
        table
      end

    end # Common

    module ControllerMethods
      include Common
    end

    # Routes = {
    #  :cell_update => :post, :table_update => :post, :cell_edit => :get
    # }

    module ViewMethods
      include Common

      # Create a table from an attribute
      def make_table(opts)
        style, node, attribute, title, table = opts[:style], opts[:node], opts[:attribute], opts[:title], opts[:table]
        case (style || '').sub('.', '')
        when ">"
          prefix = "<div class='img_right'>"
          suffix = "</div>"
        when "<"
          prefix = "<div class='img_left'>"
          suffix = "</div>"
        when "="
          prefix = "<div class='img_center'>"
          suffix = "</div>"
        else
          prefix = ''
          suffix = ''
        end

        table ||= get_table_from_json(node.prop[attribute])

        res = prefix 
        if node.can_write?
          res << "<table data-a='node[#{attribute}]' class='grid'>\n<tr>"
        else
          res << "<table><tr>"
        end

        table[1][0].each do |heading|
          res << "<th>#{ heading }</th>"
        end
        res << "</tr>\n"
        table[1][1..-1].each do |row|
          res << "<tr>\n"
          row.each do |td|
            res << "<td>#{td}</td>\n"
          end
          res << "</tr>\n"
        end
        res << "</table>\n"
        res << suffix
        res
      rescue JSON::ParserError
        "<span class='unknownLink'>could not build table from text</span>"
      end
    end

    # New better grid using JS.
    module ZafuMethods
      def r_grid
        attr = @params[:attr]
        raise parser_error("Missing 'attr' parameter") unless attr
        # Make sure it compiles
        code = RubyLess.translate(node(Node).klass, attr)
        out "<%= make_table(:attribute => #{attr.inspect}, :node => #{node(Node)}) %>"
      end
    end
  end # Grid
end # Zena

