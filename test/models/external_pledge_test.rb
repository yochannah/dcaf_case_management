require 'test_helper'

class ExternalPledgeTest < ActiveSupport::TestCase
  before do
    @user = create :user
    @patient = create :patient
    @patient.external_pledges.create created_by: @user,
                                     amount: 100,
                                     source: 'BWAH'
    @pledge = @patient.external_pledges.first
  end

  describe 'mongoid attachments' do
    it 'should have timestamps from Mongoid::Timestamps' do
      [:created_at, :updated_at].each do |field|
        assert @pledge.respond_to? field
        assert @pledge[field]
      end
    end

    it 'should respond to history methods' do
      assert @pledge.respond_to? :history_tracks
      assert @pledge.history_tracks.count > 0
    end

    it 'should have accessible userstamp methods' do
      assert @pledge.respond_to? :created_by
      assert @pledge.created_by
    end
  end

  describe 'validations' do
    [:created_by, :source, :amount].each do |field|
      it "should enforce presence of #{field}" do
        @pledge[field.to_sym] = nil
        refute @pledge.valid?
      end
    end

    it 'should scope source uniqueness to a particular document' do
      pledge = @patient.external_pledges
                       .create attributes_for(:external_pledge,
                                              amount: 200,
                                              source: 'BWAH')
      refute pledge.valid?

      pledge.source = 'Other Fund'
      assert pledge.valid?

      pt_2 = create :patient
      pledge2 = pt_2.external_pledges
                    .create attributes_for(:external_pledge,
                                           source: 'BWAH')
      assert pledge2.valid?
    end
  end

  describe 'scopes' do
    before do
      @patient.external_pledges.create! created_by: User.first,
                                        amount: 100,
                                        source: 'Bar',
                                        active: false
    end

    it 'should leave inactive pledges out unless specified queries' do
      @patient.reload
      assert_equal 1, @patient.external_pledges.count
      assert_equal 1, @patient.external_pledges.active.count
      assert_equal 2, @patient.external_pledges.unscoped.count
    end
  end
end
