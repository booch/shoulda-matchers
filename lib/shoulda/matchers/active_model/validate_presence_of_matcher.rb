module Shoulda
  module Matchers
    module ActiveModel
      # The `validate_presence_of` matcher tests usage of the
      # `validates_presence_of` validation.
      #
      #     class Robot
      #       include ActiveModel::Model
      #       attr_accessor :arms
      #
      #       validates_presence_of :arms
      #     end
      #
      #     # RSpec
      #     RSpec.describe Robot, type: :model do
      #       it { should validate_presence_of(:arms) }
      #     end
      #
      #     # Minitest (Shoulda)
      #     class RobotTest < ActiveSupport::TestCase
      #       should validate_presence_of(:arms)
      #     end
      #
      # #### Caveats
      #
      # Under Rails 4 and greater, if your model `has_secure_password` and you
      # are validating presence of the password using a record whose password
      # has already been set prior to calling the matcher, you will be
      # instructed to use a record whose password is empty instead.
      #
      # For example, given this scenario:
      #
      #     class User < ActiveRecord::Base
      #       has_secure_password validations: false
      #
      #       validates_presence_of :password
      #     end
      #
      #     RSpec.describe User, type: :model do
      #       subject { User.new(password: '123456') }
      #
      #       it { should validate_presence_of(:password) }
      #     end
      #
      # the above test will raise an error like this:
      #
      #     The validation failed because your User model declares
      #     `has_secure_password`, and `validate_presence_of` was called on a
      #     user which has `password` already set to a value. Please use a user
      #     with an empty `password` instead.
      #
      # This happens because `has_secure_password` itself overrides your model
      # so that it is impossible to set `password` to nil. This means that it is
      # impossible to test that setting `password` to nil places your model in
      # an invalid state (which in turn means that the validation itself is
      # unnecessary).
      #
      # #### Qualifiers
      #
      # ##### allow_nil
      #
      # Use `allow_nil` if your model has an optional attribute.
      #
      #   class Robot
      #     include ActiveModel::Model
      #     attr_accessor :nickname
      #
      #     validates_presence_of :nickname, allow_nil: true
      #   end
      #
      #   # RSpec
      #   RSpec.describe Robot, type: :model do
      #     it { should validate_presence_of(:nickname).allow_nil }
      #   end
      #
      #   # Minitest (Shoulda)
      #   class RobotTest < ActiveSupport::TestCase
      #     should validate_presence_of(:nickname).allow_nil
      #   end
      #
      # ##### on
      #
      # Use `on` if your validation applies only under a certain context.
      #
      #     class Robot
      #       include ActiveModel::Model
      #       attr_accessor :arms
      #
      #       validates_presence_of :arms, on: :create
      #     end
      #
      #     # RSpec
      #     RSpec.describe Robot, type: :model do
      #       it { should validate_presence_of(:arms).on(:create) }
      #     end
      #
      #     # Minitest (Shoulda)
      #     class RobotTest < ActiveSupport::TestCase
      #       should validate_presence_of(:arms).on(:create)
      #     end
      #
      # ##### with_message
      #
      # Use `with_message` if you are using a custom validation message.
      #
      #     class Robot
      #       include ActiveModel::Model
      #       attr_accessor :legs
      #
      #       validates_presence_of :legs, message: 'Robot has no legs'
      #     end
      #
      #     # RSpec
      #     RSpec.describe Robot, type: :model do
      #       it do
      #         should validate_presence_of(:legs).
      #           with_message('Robot has no legs')
      #       end
      #     end
      #
      #     # Minitest (Shoulda)
      #     class RobotTest < ActiveSupport::TestCase
      #       should validate_presence_of(:legs).
      #         with_message('Robot has no legs')
      #     end
      #
      # @return [ValidatePresenceOfMatcher]
      #
      def validate_presence_of(attr)
        ValidatePresenceOfMatcher.new(attr)
      end

      # @private
      class ValidatePresenceOfMatcher < ValidationMatcher
        include Qualifiers::AllowNil

        def initialize(attribute)
          super
          @expected_message = :blank
        end

        def matches?(subject)
          super(subject)

          possibly_ignore_interference_by_writer

          if secure_password_being_validated?
            ignore_interference_by_writer.default_to(when: :blank?)

            disallowed_values.all? do |value|
              disallows_and_double_checks_value_of!(value)
            end
          else
            (!expects_to_allow_nil? || allows_value_of(nil)) &&
              disallowed_values.all? do |value|
                disallows_original_or_typecast_value?(value)
              end
          end
        end

        def does_not_match?(subject)
          super(subject)

          possibly_ignore_interference_by_writer

          if secure_password_being_validated?
            ignore_interference_by_writer.default_to(when: :blank?)

            disallowed_values.any? do |value|
              allows_and_double_checks_value_of!(value)
            end
          else
            (expects_to_allow_nil? && !allows_value_of(nil)) ||
              disallowed_values.any? do |value|
                allows_original_or_typecast_value?(value)
              end
          end
        end

        def simple_description
          "validate that :#{@attribute} cannot be empty/falsy"
        end

        def failure_message
          message = super

          if should_add_footnote_about_belongs_to?
            message << "\n\n"
            message << Shoulda::Matchers.word_wrap(<<-MESSAGE.strip, indent: 2)
You're getting this error because #{reason_for_existing_presence_validation}.
*This* presence validation doesn't use "can't be blank", the usual validation
message, but "must exist" instead.

With that said, did you know that the `belong_to` matcher can test this
validation for you? Instead of using `validate_presence_of`, try the following
instead:

      it { should #{representation_of_belongs_to} }
            MESSAGE
          end

          message
        end

        private

        def secure_password_being_validated?
          Shoulda::Matchers::RailsShim.digestible_attributes_in(@subject).
            include?(@attribute)
        end

        def possibly_ignore_interference_by_writer
          if secure_password_being_validated?
            ignore_interference_by_writer.default_to(when: :blank?)
          end
        end

        def allows_and_double_checks_value_of!(value)
          allows_value_of(value, @expected_message)
        rescue ActiveModel::AllowValueMatcher::AttributeChangedValueError
          raise ActiveModel::CouldNotSetPasswordError.create(model)
        end

        def allows_original_or_typecast_value?(value)
          allows_value_of(value, @expected_message)
        end

        def disallows_and_double_checks_value_of!(value)
          disallows_value_of(value, @expected_message)
        rescue ActiveModel::AllowValueMatcher::AttributeChangedValueError
          raise ActiveModel::CouldNotSetPasswordError.create(model)
        end

        def disallows_original_or_typecast_value?(value)
          disallows_value_of(value, @expected_message)
        end

        def disallowed_values
          if collection?
            [Array.new]
          else
            values = []

            if !association_being_validated?
              values << ''
            end

            if !expects_to_allow_nil?
              values << nil
            end

            values
          end
        end

        def collection?
          if association_reflection
            [:has_many, :has_and_belongs_to_many].include?(
              association_reflection.macro,
            )
          else
            false
          end
        end

        def should_add_footnote_about_belongs_to?
          belongs_to_association_being_validated? &&
            presence_validation_exists_on_attribute?
        end

        def reason_for_existing_presence_validation
          if belongs_to_association_configured_to_be_required?
            "you've instructed your `belongs_to` association to add a " +
              'presence validation to the attribute'
          else
            # assume ::ActiveRecord::Base.belongs_to_required_by_default == true
            'ActiveRecord is configured to add a presence validation to all ' +
              '`belongs_to` associations, and this includes yours'
          end
        end

        def representation_of_belongs_to
          'belong_to(:parent)'.tap do |str|
            if association_reflection.options.include?(:optional)
              str << ".optional(#{association_reflection.options[:optional]})"
            end
          end
        end

        def belongs_to_association_configured_to_be_required?
          association_reflection.options[:optional] == false ||
            association_reflection.options[:required] == true
        end

        def belongs_to_association_being_validated?
          association_being_validated? &&
            association_reflection.macro == :belongs_to
        end

        def association_being_validated?
          !!association_reflection
        end

        def association_reflection
          model.respond_to?(:reflect_on_association) &&
            model.reflect_on_association(@attribute)
        end

        def presence_validation_exists_on_attribute?
          model._validators.include?(@attribute)
        end

        def model
          @subject.class
        end
      end
    end
  end
end
