require File.dirname(__FILE__) + '/../test_helper'

class GroupTest < ZenaTestUnit
  
  def test_public_group
    login(:ant)
    grp = groups(:public)
    assert grp.public_group?, "'public' is the public group."
    grp = groups(:site)
    assert !grp.public_group?, "'site' is not the public group."
    
    login(:whale)
    grp = groups(:public)
    assert !grp.public_group?, "'public' is not the public group for 'ocean.host'."
  end
  
  def test_site_group
    login(:ant)
    grp = groups(:site)
    assert grp.site_group?, "'site' is the site group."
    grp = groups(:admin)
    assert !grp.site_group?, "'admin' is not the site group."
    
    login(:whale)
    grp = groups(:site)
    assert !grp.site_group?, "'site' is not the site group for 'ocean.host'."
  end
  
  def test_user_ids
    sitegrp = groups(:site)
    assert_equal [users_id(:ant),users_id(:lion),users_id(:tiger)], sitegrp.user_ids
  end
  
  def test_users_password_nil
    sitegrp = groups(:site)
    users = sitegrp.users
    assert_equal 3, users.size
    assert_nil users[0][:password]
    assert_nil users[1][:password]
    assert_nil users[2][:password]
  end
  
  def test_dont_destroy_public_or_admin
    login(:lion)
    grp = groups(:public)
    assert_raise(Zena::AccessViolation) { grp.destroy }
    grp = groups(:site)
    assert_raise(Zena::AccessViolation) { grp.destroy }
  end
  
  def test_site_id
    login(:lion)
    grp = secure(Group) { Group.create(:name=>'test') }
    assert !grp.new_record?, "Not a new record"
    assert_equal sites_id(:zena), grp[:site_id]
    assert grp.destroy, "Can destroy group"
  end
  
  def test_cannot_set_site_id
    login(:tiger)
    grp = groups(:site)
    assert_raise(Zena::AccessViolation) { grp.site_id = sites_id(:ocean) }
  end
  
  def test_add_to_site
    login(:tiger)
    group = secure(Group) { Group.new(:name=>'bidule') }
    assert !group.save
    group = groups(:site)
    assert !group.update_attributes(:name=>'stressedWorkers')
    
    login(:lion)
    group = secure(Group) { Group.new(:name=>'bidule') }
    assert group.save
    assert_equal sites_id(:zena), group.site_id
    group = groups(:site)
    assert group.update_attributes(:name=>'stressedWorkers')
  end
  
  def test_add_user
    login(:lion)
    group = secure(Group) { Group.new(:name=>'bidule') }
    assert group.save
    group = Group.find(group[:id])
    assert group.update_attributes(:name=>'stressedWorkers', :user_ids=>[users_id(:ant)])
    assert group.users.include?(users(:ant))
    group = Group.find(group[:id])
    # in site
    assert group.update_attributes(:name=>'stressedWorkers', :user_ids=>[users_id(:tiger)])
    assert !group.users.include?(users(:ant))
    assert group.users.include?(users(:tiger))
    # not in site
    assert !group.update_attributes(:name=>'stressedWorkers', :user_ids=>[users_id(:whale)])
  end
  
  def test_can_add_to_admin
    login(:lion)
    group = groups(:admin)
    assert group.update_attributes(:user_ids=>[users_id(:ant),users_id(:lion)])
    assert groups(:admin).users.include?(visitor)
    assert groups(:admin).users.include?(users(:ant))
  end
  
  def test_cannot_update_site_or_public
    login(:lion)
    group = groups(:public)
    assert !group.update_attributes(:user_ids=>[])
    group = groups(:site)
    assert !group.update_attributes(:user_ids=>[])
  end
end
