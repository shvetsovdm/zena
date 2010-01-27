module Zena
  module Use
    # When you include this module into a class, it will automatically clone itself
    # depending on the call to should_clone?
    module AutoVersion
      def self.included(base)
        base.before_save :prepare_save_or_clone
      end

      def should_clone?
        raise Exception.new("You should implement 'should_clone?' in your model (return true for a new version, false to update).")
      end

      def prepare_save_or_clone
        if !new_record? && should_clone?
          self[:id] = nil
          self[:created_at] = nil
          self[:updated_at] = nil
          @new_record = true
        end
      end
    end
  end
end