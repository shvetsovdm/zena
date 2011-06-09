module Bricks
  module Acls
    module AuthorizationMethods
    end

    module UserMethods
      def self.included(base)
        base.class_eval do
          attr_accessor :exec_acl
          alias_method_chain :get_skin, :acls
          alias_method_chain :find_node, :acls
          attr_accessible :use_acls
        end
      end

      def acl_authorized?(action, params, base_node = nil)
        node = nil
        group_ids_bak = group_ids.dup
        acls(action).each do |acl|
          # Load exec_group to execute query
          if acl.exec_group_id
            @group_ids = group_ids_bak + [acl.exec_group_id]
          end
          base_node ||= self.node_without_secure
          if node = acl.authorize?(base_node, params)
            self.exec_acl = acl
            # Keep loaded exec_group
            return node
          end
        end
        nil
      ensure
        unless self.exec_acl
          # Remove loaded exec_group
          @group_ids = group_ids_bak
        end
      end

      # Find all acls for the visitor for a given action. The action should
      # be one of the following: 'create', 'read', 'update', 'delete'. See
      # Acl::ACTIONS.
      def acls(action)
        secure(Acl) { Acl.find(:all,
          :conditions => ['group_id IN (?) and action = ?', group_ids, action],
          :order => 'priority DESC'
        )} || []
      end

      def get_skin_with_acls(node)
        exec_acl ? exec_acl.exec_skin : get_skin_without_acls(node)
      end

      def find_node_with_acls(path, zip, name, params, method)
        find_node_without_acls(path, zip, name, params, method)
      rescue ActiveRecord::RecordNotFound
        raise unless visitor.use_acls?
        acl_params = params.dup
        if name =~ /^\d+$/
          acl_params[:id] = name
        elsif name
          # Cannot use acl to find by path
          return nil
        else
          acl_params[:id] = zip
        end
        if node = visitor.acl_authorized?(::Acl::ACTION_FROM_METHOD[method], acl_params)
          node
        else
          raise
        end
      end
    end # UserMethods
  end # Acls
end # Bricks