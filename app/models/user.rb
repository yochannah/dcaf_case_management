# Object representing a case manager.
# Fields are all devise settings; most of the methods relate to call list mgmt.
class User
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Userstamp::User
  include Mongoid::History::Trackable
  extend Enumerize

  include UserSearchable
  include CallListable
  track_history on: fields.keys + [:updated_by_id],
                  version_field: :version,
                  track_create: true,
                  track_update: true,
                  track_destroy: true

  after_create :send_account_created_email, if: :persisted?

  # Devise modules
  devise  :database_authenticatable,
          :registerable,
          :recoverable,
          :trackable,
          :validatable,
          :lockable,
          :timeoutable,
          :omniauthable, omniauth_providers: [:google_oauth2]
  # :rememberable
  # :confirmable

  # Callbacks
  after_update :send_password_change_email, if: :needs_password_change_email?

  # Relationships
  has_many :call_list_entries

  # Fields
  # Non-devise generated
  field :name, type: String
  field :line, type: String
  field :role, default: :cm

  enumerize :role, in: [:cm, :admin, :data_volunteer], predicates: true

  ## Database authenticatable
  field :email,              type: String, default: ''
  field :encrypted_password, type: String, default: ''

  ## Recoverable
  field :reset_password_token,   type: String
  field :reset_password_sent_at, type: Time

  ## Rememberable
  # field :remember_created_at, type: Time

  ## Trackable
  field :sign_in_count,      type: Integer, default: 0
  field :current_sign_in_at, type: Time
  field :last_sign_in_at,    type: Time
  field :current_sign_in_ip, type: String
  field :last_sign_in_ip,    type: String

  ## Confirmable
  # field :confirmation_token,   type: String
  # field :confirmed_at,         type: Time
  # field :confirmation_sent_at, type: Time
  # field :unconfirmed_email,    type: String # Only if using reconfirmable

  ## Lockable
  field :failed_attempts, type: Integer, default: 0
  # field :unlock_token,    type: String
  field :locked_at,       type: Time

  # An extra hard shutoff field for when a fund wants to shut off a user acct.
  # We call this disabling in the app, but users/CMs see this as 'Lock/Unlock'.
  # We do this because Devise calls a temporary account shutoff because of too
  # many failed attempts an account lock.
  field :disabled_by_fund, type: Boolean, default: false

  # Validations
  # email presence validated through Devise
  validates :name, presence: true
  validates :role, presence: true
  validate :secure_password, if: :updating_password?
  # i18n-tasks-use t('errors.messages.password.password_strength')
  validates :password, password_strength: {use_dictionary: true}, if: :updating_password?


  TIME_BEFORE_DISABLED_BY_FUND = 9.months

  def updating_password?
    return !password.nil?
  end

  def secure_password
    pc = verify_password_complexity
    if pc == false
      errors.add :password, 'Password must include at least one lowercase ' \
                            'letter, one uppercase letter, and one digit. ' \
                            "Forbidden words include #{FUND} and password."
    end
  end

  def self.from_omniauth(access_token)
    data = access_token.info
    user = User.find_by email: data['email']

    user
  end

  def toggle_disabled_by_fund
    # Since toggle skips callbacks...
    update disabled_by_fund: !disabled_by_fund
  end

  def self.disable_inactive_users
    cutoff_date = Time.zone.now - TIME_BEFORE_DISABLED_BY_FUND
    inactive_has_logged_in = where(:role.nin => [:admin],
                                   :current_sign_in_at.lt => cutoff_date)
    inactive_no_logins = where(:role.nin => [:admin],
                               :current_sign_in_at => nil,
                               :created_at.lt => cutoff_date)
    [inactive_no_logins, inactive_has_logged_in].each do |set|
      set.update disabled_by_fund: true
    end
  end

  def admin?
    role == 'admin'
  end

  def allowed_data_access?
    admin? || data_volunteer?
  end

  private

  def verify_password_complexity
    return false unless password.length >= 8 # length at least 8
    return false if (password =~ /[a-z]/).nil? # at least one lowercase
    return false if (password =~ /[A-Z]/).nil? # at least one uppercase
    return false if (password =~ /[0-9]/).nil? # at least one digit
    # Make sure no bad words are in there
    fund = FUND.downcase
    return false unless password.downcase[/(password|#{fund})/].nil?
    true
  end

  def needs_password_change_email?
    encrypted_password_changed? && persisted?
  end

  def send_password_change_email
    # @user = User.find(id)
    UserMailer.password_changed(id).deliver_now
  end

  def send_account_created_email
    UserMailer.account_created(id).deliver_now
  end
end
