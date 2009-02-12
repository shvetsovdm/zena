module Zena
  module Acts
    module Multiversion
      # this is called when the module is included into the 'base' module
      def self.included(base)
        # add all methods from the module "AddActsAsMethod" to the 'base' module
        base.extend AddActsAsMethods
      end
      
      module AddActsAsMethods
        def acts_as_multiversioned(opts = {})
          opts.reverse_merge!({
            :class_name => 'Version'
          })
          
          # TODO: remove for Observers.
          after_save        :after_all
          
          has_many :versions, :inverse => self.to_s.underscore,  :class_name => opts[:class_name],
                   :order=>"number DESC", :dependent => :destroy
          has_one  :redaction, :inverse => self.to_s.underscore, :class_name => opts[:class_name],
                   :conditions => '(status = 30 OR status = 50) AND lang = #{Node.connection.quote(visitor.lang)}',
                   :order => 'status ASC', :autosave => true
          has_many :editions, :class_name=>"Version",
                   :conditions=>"publish_from <= now() AND status = #{Zena::Status[:pub]}", :order=>'lang'
          
          before_validation :set_status_before_validation
          validate      :status_validation
          before_create :cache_version_status_before_create
          before_update :cache_version_status_before_update
          after_save    :remove_publications_after_save
          
          public
          
          include Zena::Acts::MultiversionImpl::InstanceMethods
          class << self
            include Zena::Acts::MultiversionImpl::ClassMethods
          end
          
          add_transition(:publish, :from => (0..49), :to => 50) do |r|
            xxx
          end
            StatusValidations = {
              #from      #validation #to
             [(0..49),   50] => :publish, #  :pub
             [(30..39),  40] => :propose, #  :prop
             [(30..39),  35] => :propose, #  :prop_with
             [(50..50),  30] => :redit,
             [(0..39),   30] => :update_attributes,
             [(40..49),  30] => :refuse,
            }.freeze
        end
        
        def act_as_content
          class_eval do
            def preload_version(v)
              @version = v
            end
            
            # FIXME: replace by belongs_to :version ?
            def version
              @version ||= Version.find(self[:version_id])
            end
          end
        end
      end
    end
    
    module MultiversionImpl
      module InstanceMethods
        
        # VERSION
        def version=(v)
          if v.kind_of?(Version)
            @version = v
          end
        end
        
        def can_edit?
          can_edit_lang?
        end
        
        def can_edit_lang?(lang=nil)
          return false unless can_write?
          if lang
            # can we create a new redaction for this lang ?
            v = versions.find(:first, :conditions=>["status >= #{Zena::Status[:red]} AND status < #{Zena::Status[:pub]} AND lang=?", lang])
            v == nil
          else
            # can we create a new redaction in the current context ?
            # there can only be one redaction/proposition per lang per node. Only the owner of the red can edit
            v = versions.find(:first, :conditions=>["status >= #{Zena::Status[:red]} AND status < #{Zena::Status[:pub]} AND lang=?", visitor.lang])
            v == nil || (v.status == Zena::Status[:red] && v.user_id == visitor[:id])
          end 
        rescue ActiveRecord::RecordNotFound
          true
        end
        
        # Try to set the node's version to a redaction. If lang is specified
        def edit!(lang = visitor.lang, publish_after_save = false)
          redaction(lang, publish_after_save)
        end
        
        def edit_content!
          redaction && redaction.redaction_content
        end
        
        # return an array of published versions
        def traductions(opts={})
          if opts == {}
            trad = editions
          else
            trad = editions.find(:all, opts)
          end

          # FIXME: we should not need to store node like this. Can be removed when we cache found records from their ids
          # (using DataMapper or simply our visitor)
          trad.map! do |t|
            t.set_node(self) # make sure relation is kept and we do not reload a node that is not secured
            t
          end
          trad == [] ? nil : trad
        end
        
        # can propose for validation
        def can_propose?
          can_apply?(:propose)
        end
        
        # people who can publish:
        # * people who #can_visible? if +status+ >= prop or owner
        # * people who #can_manage? if node is private
        def can_publish?
          can_apply?(:publish)
        end
        
        # Can refuse a publication. Same rights as can_publish? if the current version is a redaction.
        def can_refuse?
          can_apply?(:refuse)
        end
        
        # Can remove publication
        def can_unpublish?(v=version)
          can_apply?(:unpublish, v)
        end
        
        # Can destroy current version ? (only logged in user can destroy)
        def can_destroy_version?(v=version)
          can_apply?(:destroy_version, v)
        end
        
        # Return true if the node is not a reference for any other node
        def empty?
          return true if new_record?
          0 == self.class.count_by_sql("SELECT COUNT(*) FROM #{self.class.table_name} WHERE #{ref_field} = #{self[:id]}")
        end
        
        def transition_allowed(prev_status, curr_status)
          self.class.transitions.each do |t|
            from, to = t[:from], t[:to]
            if curr_status == to && from.include?(prev_status)
              return t[:validation].call(self)
            end
          end
        end
        
        def all_transitions_allowed
          @allowed_transitions ||= begin
            prev_status = version.status_was.to_i
            curr_status = version.status.to_i
            allowed = []
            self.class.transitions.each do |t|
              from, to = t[:from], t[:to]
              if curr_status == to && from.include?(prev_status)
                allowed << t if t[:validation].call(self)
              end
            end
            allowed
          end
        end
        
        # Returns false is the current visitor does not have enough rights to perform the action.
        def can_apply?(method, v=version)
          return true  if visitor.is_su?
          prev_status = v.status_was.to_i
          case method
          when :update_attributes
            can_write?
          when :drive # ?
            can_drive?
          when :propose, :backup
            v.user_id == visitor[:id] && prev_status == Zena::Status[:red]
          when :refuse
            prev_status > Zena::Status[:red] && can_apply?(:publish)
          when :publish  
            if prev_status == Zena::Status[:pub]
              errors.add('base', 'already published.')
              return false
            end
            prev_status < Zena::Status[:pub] && 
            ( ( can_visible_was_true? && (prev_status > Zena::Status[:red] || prev_status == Zena::Status[:rep] || v.user_id_was == visitor[:id]) ) ||
              ( can_manage_was_true?  && private_was_true? )
            )
          when :unpublish
            can_drive? && prev_status == Zena::Status[:pub]
          when :remove
            (can_drive? || v.user_id == visitor[:id] ) && prev_status <= Zena::Status[:red] && prev_status > Zena::Status[:rem]
          when :redit
            can_edit? && v.user_id == visitor[:id]
          when :edit
            can_edit?
          when :destroy_version
            # anonymous users cannot destroy
            can_drive? && prev_status == Zena::Status[:rem] && !visitor.is_anon? && (self.versions.count > 1 || empty?)
          end
        end
        
        # Gateway to all modifications of the node or it's versions.
        def apply(method, *args)
          unless can_apply?(method)
            errors.add('base', 'you do not have the rights to do this') if errors.empty?
            return false
          end
          res = case method
          when :update_attributes
            do_update_attributes(args[0])
          when :propose
            self.redaction_attributes = {
              'status' => args[0] || Zena::Status[:prop]
            }
            save
          when :backup
            version.status = Zena::Status[:rep]
            @redaction = nil
            redaction.save if version.save
          when :refuse
            version.status = Zena::Status[:red]
            version.save && after_refuse && update_max_status
          when :publish
            self.redaction_attributes = {
              'publish_from' => version.publish_from || Time.now,
              'status'       => Zena::Status[:pub]
            }
            save
          when :unpublish
            version.status = Zena::Status[:rem]
            if version.save
              update_publish_from && update_max_status && after_unpublish
            else
              false
            end
          when :remove
            version.status = Zena::Status[:rem]
            if version.save
              update_publish_from && update_max_status && after_remove
            else
              false
            end
          when :redit
            version.status = Zena::Status[:red]
            if version.save
              update_publish_from && update_max_status && after_redit
            else
              false
            end
          when :destroy_version
            if versions.count == 1
              version.destroy && self.destroy
            else
              version.destroy
            end
          end
        end
        
        # Propose for publication
        def propose(prop_status=Zena::Status[:prop])
          apply(:propose, prop_status)
        end
        
        # Backup a redaction (create a new version)
        # TODO: test
        def backup
          apply(:backup)
        end
        
        # Refuse publication
        def refuse
          apply(:refuse)
        end
        
        # publish if version status is : redaction, proposition, replaced or removed
        # if version to publish is 'rem' or 'red' or 'prop' : old publication => 'replaced'
        # if version to publish is 'rep' : old publication => 'removed'
        def publish(pub_time=nil)
          apply(:publish, pub_time)
        end
        
        def unpublish
          apply(:unpublish)
        end
        
        # A published version can be removed by the members of the publish group
        # A redaction can be removed by it's owner
        def remove
          apply(:remove)
        end
        
        # Edit again a previously published/removed version.
        def redit
          apply(:redit)
        end
        
        # Versions can be destroyed if they are in 'deleted' status.
        # Destroying the last version completely removes the node (it must thus be empty)
        def destroy_version
          apply(:destroy_version)
        end
        
        # Set +publish_from+ to the minimum publication time of all editions
        def get_publish_from
          pub_string  = (self.class.connection.select_one("select publish_from from #{version.class.table_name} WHERE node_id='#{self[:id]}' and status = #{Zena::Status[:pub]} order by publish_from DESC LIMIT 1") || {})['publish_from']
          ActiveRecord::ConnectionAdapters::Column.string_to_time(pub_string)
        end
        
        # Set +max_status+ to the maximum status of all versions
        def get_max_status(version = self.version)
          vers_table = version.class.table_name
          new_max    = self.class.connection.select_one("select #{vers_table}.status from #{vers_table} WHERE #{vers_table}.node_id='#{self[:id]}' order by #{vers_table}.status DESC LIMIT 1")['status']
          new_max.to_i
        end
        
        # Update an node's attributes or the node's version/content attributes. If the attributes contains only
        # :v_... or :c_... keys, then only the version will be saved. If the attributes does not contain any :v_... or :c_...
        # attributes, only the node is saved, without creating a new version.
        def update_attributes(new_attributes)
          apply(:update_attributes,new_attributes)
        end
        
        # Return the current version. If @version was not set, this is a normal find or a new record. We have to find
        # a suitable edition :
        # * if new_record?, create a new redaction
        # * find user redaction or proposition in the current lang 
        # * find an edition for current lang
        # * find an edition in the reference lang for this node
        # * find the first publication
        # If 'key' is set to :pub, only find the published versions. If key is a number, find the version with this number. 
        def version(key=nil) #:doc:
          @version ||= if new_record?
            build_redaction('lang' => visitor.lang)
          else
            versions.find(:first, 
              :select     => "*, (lang = #{Node.connection.quote(visitor.lang)}) as lang_ok, (lang = #{Node.connection.quote(ref_lang)}) as ref_ok",
              :conditions => [ "(status >= #{Zena::Status[:red]} AND user_id = ? AND lang = ?) OR status >= ?", 
                                      visitor.id, visitor.lang, (can_drive? ? Zena::Status[:prop] : Zena::Status[:pub])],
              :order      => "lang_ok DESC, ref_ok DESC, status ASC, publish_from ASC")
          end
=begin
          return @version if @version
          
          if key && !key.kind_of?(Symbol) && !new_record?
            if visitor.is_su?
              @version = secure!(Version) { Version.find(:first, :conditions => ["node_id = ? AND number = ?", self[:id], key]) }
            elsif can_drive?
              @version = secure!(Version) { Version.find(:first, :conditions => ["node_id = ? AND number = ? AND (user_id = ? OR status <> ?)", self[:id], key, visitor[:id], Zena::Status[:red]]) }
            else
              @version = secure!(Version) { Version.find(:first, :conditions => ["node_id = ? AND number = ? AND (user_id = ? OR status >= ?)", self[:id], key, visitor[:id], Zena::Status[:pub]]) }
            end
          else
            min_status = (key == :pub) ? Zena::Status[:pub] : Zena::Status[:red]
            
            if new_record?
              @version = version_class.new
              # owner and lang set in secure_scope
              @version.status = Zena::Status[:red]
            elsif can_drive?
              # sees propositions
              lang = visitor.lang.gsub(/[^\w]/,'')
              @version =  Version.find(:first,
                            :select=>"*, (lang = '#{lang}') as lang_ok, (lang = '#{ref_lang}') as ref_ok",
                            :conditions=>[ "((status >= ? AND user_id = ? AND lang = ?) OR status > ?) AND node_id = ?", 
                                            min_status, visitor[:id], lang, Zena::Status[:red], self[:id] ],
                            :order=>"lang_ok DESC, ref_ok DESC, status ASC ")
              if !@version
                @version = versions.find(:first, :order=>'id DESC')
              end
            else
              # only own redactions and published versions
              lang = visitor.lang.gsub(/[^\w]/,'')
              @version =  Version.find(:first,
                            :select=>"*, (lang = '#{lang}') as lang_ok, (lang = '#{ref_lang}') as ref_ok",
                            :conditions=>[ "((status >= ? AND user_id = ? AND lang = ?) OR status = ?) and node_id = ?", 
                                            min_status, visitor[:id], lang, Zena::Status[:pub], self[:id] ],
                            :order=>"lang_ok DESC, ref_ok DESC, status ASC, publish_from ASC")

            end
            
            if @version.nil?
              raise Exception.new("#{self.class} #{self[:id]} does not have any version !!")
            end
          end
          @version.node = self if @version # preload self as node in version
          @version
=end
        end
        
        # Define attributes for the current redaction.
        def redaction_attributes=(attrs)
          attrs.reverse_merge!('lang' => visitor.lang)
          auto_publish = (attrs['status'].to_i == Zena::Status[:pub] || current_site[:auto_publish])
          if new_record?
            # new redaction
            build_redaction(attrs)
          elsif !can_write?    
            errors.add('base', 'you do not have the rights to edit this node')
          elsif @redaction = self.redaction
            # redaction candidate, make sure it can be used
            if    (@redaction.user_id == visitor.id)                                    &&  # same author
                  (@redaction.status  == Zena::Status[:red])                            &&  # redaction status
              # ok                                                                    
              @redaction.attributes = attrs                                            
            elsif (@redaction.user_id == visitor.id)                                    &&  # same author
                  (@redaction.status  == Zena::Status[:pub])                            &&  # publication
                  (auto_publish)                                                        &&  # auto_publish
                  (Time.now < @redaction.updated_at_was + current_site.redit_time.to_i)     # redit time
              # ok
              @redaction.attributes = attrs
            elsif (@redaction.status  == Zena::Status[:red])                                # not same author
              errors.add('base', "(#{@redaction.user.login}) is editing this node")
            else
              # cannot reuse publication (out of redit time, no auto_publish, not same author)
              # make a copy
              build_redaction_from(@redaction, attrs)
            end
          else
            # no redaction candidate
            # copy current version
            build_redaction_from(version, attrs)
          end
        end
        
        private
          def set_status_before_validation
            multiversion_before_validation_on_create if new_record?
            if @redaction
              target = @redaction.target # avoid "method_missing" calls in AssociationProxy
              target.status ||= current_site[:auto_publish] ? Zena::Status[:pub] : Zena::Status[:red]
              target.publish_from = target.status.to_i == Zena::Status[:pub] ? (target.publish_from || Time.now) : nil
            end
          end
          
          # Called before create validations, this method is responsible for setting up
          # the initial redaction.
          def multiversion_before_validation_on_create
            build_redaction_from(nil, {}) unless @redaction
            self.max_status   = version.status
            self.publish_from = version.publish_from
          end
          
          def status_validation
            return true unless @redaction && version.status_changed?
            validation_op = nil
            prev_status = version.status_was.to_i
            curr_status = version.status.to_i
            StatusValidations.each do |ft, sym|
              src_status, target_status = ft
              if curr_status == target_status && src_status.include?(prev_status)
                validation_op = sym
                break
              end
            end
            if validation_op
              errors.add_to_base("You do not have the rights to #{validation_op.to_s.gsub('_', ' ')}") unless can_apply?(validation_op)
            else
              version.errors.add('status', "Invalid status change")
            end
          end
          
          def cache_version_status_before_create
            self.max_status   = version.status
            self.publish_from = version.publish_from
            true
          end
          
          def cache_version_status_before_update
            self.updated_at = Time.now
            if @auto_publish
              self.max_status   = Zena::Status[:pub]
              self.publish_from = [get_publish_from, version.publish_from].min
              @old_publication_to_remove = [version.class.fetch_ids "node_id = '#{self[:id]}' AND lang = '#{version[:lang]}' AND status = '#{Zena::Status[:pub]}' AND id != '#{version.id}'", (version.status_was == Zena::Status[:rep] ? Zena::Status[:rem] : Zena::Status[:rep])]
              @auto_publish = nil
            else
              if version.status_changed?
                if version.status.to_i > max_status
                  # version's status went up
                  self.max_status = version.status
                elsif version.status_was == max_status && version.status.changed?
                  # version's status went down
                  self.max_status   = [get_max_status, version.status.to_i].max
                  self.publish_from = get_publish_from if version.status_was == Zena::Status[:pub]
                end
              end
            end
            true
          end
          
          def remove_publications_after_save
            if @old_publication_to_remove
              self.class.connection.execute "UPDATE #{version.class.table_name} SET status = '#{@old_publication_to_remove[1]}' WHERE id IN (#{@old_publication_to_remove[0].join(', ')})" unless @old_publication_to_remove[0] == []
              
              res = after_publish(pub_time) && update_publish_from && update_max_status
              
              # TODO: can we avoid this ? 
              # self.class.connection.execute "UPDATE #{self.class.table_name} SET updated_at = #{self.class.connection.quote(Time.now)} WHERE id=#{self[:id].to_i}" unless new_record?
            end
            
            @old_publication_to_remove = nil
            true
          end
          
          # Create a new redaction from a version.
          def build_redaction_from(version, new_attributes)
            if version
              attrs = version.attributes.merge({
                'status'       => Zena::Status[:red],
                'user_id'      => visitor.id,
                'type'         => nil,
                'node_id'      => nil,
                'comment'      => nil,
                'number'       => nil,
                'publish_from' => nil,
                'created_at'   => nil,
                'updated_at'   => nil,
                'content_id'   => nil
              }).reject {|k,v| v.nil? || k =~ /_ok$/}
            
              build_redaction(attrs.merge(new_attributes))
              @redaction.content_id = version.content_id || version.id if version.content_class
            
              # copy dynamic attributes
              @redaction.dyn = version.dyn
            else
              build_redaction
            end
            @version = @redaction.target
          end
        
          def do_update_attributes(new_attributes)
            self.attributes = new_attributes
            save
          end
        
          def update_attribute_without_fuss(att, value)
            self[att] = value
            if value.kind_of?(Time)
              value = value.strftime("'%Y-%m-%d %H:%M:%S'")
            elsif value.nil?
              value = "NULL"
            else
              value = "'#{value}'"
            end
            self.class.connection.execute "UPDATE #{self.class.table_name} SET #{att}=#{value} WHERE id=#{self[:id]}"
          end

          # Any attribute starting with 'v_' belongs to the 'version' or 'redaction'
          # Any attribute starting with 'c_' belongs to the 'version' or 'redaction' content
          # FIXME: performance: create methods on the fly so that next calls will not pass through 'method_missing'. #189.
          # FIXME: this should not be used anymore. Remove.
          def method_missing(meth, *args)
            if meth.to_s =~ /^(v_|c_|d_)(([\w_\?]+)(=?))$/
              target = $1
              method = $2
              value  = $3
              mode   = $4
              if mode == '='
                begin
                  # set
                  unless recipient = redaction
                    # remove trailing '='
                    redaction_error(meth.to_s[0..-2], "could not be set (no redaction)")
                    return
                  end
                
                  case target
                  when 'c_'
                    if recipient.content_class && recipient = recipient.redaction_content
                      recipient.send(method,*args)
                    else
                      redaction_error(meth.to_s[0..-2], "cannot be set") # remove trailing '='
                    end
                  when 'd_'
                    recipient.dyn[method[0..-2]] = args[0]
                  else
                    recipient.send(method,*args)
                  end
                rescue NoMethodError
                  # bad attribute, just ignore
                end
              else
                # read
                recipient = version
                if target == 'd_'
                  version.dyn[method]
                else
                  recipient = recipient.content if target == 'c_'
                  return nil unless recipient
                  begin
                    recipient.send(method,*args)
                  rescue NoMethodError
                    # bad attribute
                    return nil
                  end
                end
              end
            else
              super
            end
          end
          
          def version_class
            self.class.version_class
          end
      end
      
      module ClassMethods
        @@transitions = {}
        
        def transitions
          @@transitions[self] ||= {}
        end
        
        def add_transition(name, args, &block)
          self.transitions << args.merge(:name => name, :validate => block)
        end
        
        # Default version class (should usually be overwritten)
        def version_class
          Version
        end
        
        # Find a node based on a version id
        def version(version_id)
          version = Version.find(version_id.to_i)
          node = self.find(version.node_id)
          node.version = version
          node.eval_with_visitor 'errors.add("base", "you do not have the rights to do this") unless version.status == 50 || can_drive? || version.user_id == visitor[:id]'
        end
      end
    end
  end
end