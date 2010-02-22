require 'test_helper'
require 'fileutils'

class DocumentTest < Zena::Unit::TestCase

  self.use_transactional_fixtures = false

  context 'On create' do
    context 'a Document' do
      setup { login(:ant) }
      subject do
          @doc = secure!(Document) { Document.create( :parent_id=>nodes_id(:cleanWater),
                                                    :file => uploaded_pdf('water.pdf') ) }
      end

      should 'save object in database' do
        assert !subject.new_record?
      end

      should 'save file in file system' do
        assert File.exist?(subject.version.filepath)
      end

      should 'save content type in properties' do
        assert_equal 'application/pdf', subject.prop['content_type']
      end

      should 'save extension in properties' do
        assert_equal 'pdf', subject.prop['ext']
      end

      should 'save title in version' do
        assert_not_nil subject.version.title
      end

      should 'save name in document (node)' do
        assert_not_nil subject[:name]
      end

      should 'save fullpath in document (node)' do
        assert_not_nil subject[:fullpath]
      end

      should 'save user_id in attachment' do
        assert_equal users_id(:ant), subject.version.attachment.user_id
      end

      should 'save site_id in attachment' do
        assert_equal sites_id(:zena), subject.version.attachment.site_id
      end
    end # a Document

    context 'with same name' do
      setup do
        login(:tiger)
      end
      subject do
        secure!(Document) { Document.create( :parent_id => nodes_id(:cleanWater),
                                                   :title => 'lake',
                                                   :file  => uploaded_pdf('water.pdf') ) }
      end

      should 'save name with increment' do
        assert_equal 'lake-1', subject.name
      end

      should 'save version title with increment' do
        assert_equal 'lake-1', subject.version.title
      end
    end # with same name

    context 'without file' do
      setup do
        login(:ant)
      end
      subject do
        secure!(Document) { Document.create(:parent_id=>nodes_id(:cleanWater), :name=>'lalala') }
      end

      should 'save record on database' do
        assert !subject.new_record?
      end

      should 'save text/plain as content type' do
        assert_equal 'text/plain', subject.content_type
      end
    end # without file

    context 'with content type specified' do
      setup do
        login(:tiger)
      end
      subject do
        secure!(Document) { Document.create("content_type"=>"text/css",
                                            "parent_id"=>nodes_id(:cleanWater),
                                            :file => uploaded_text('some.txt') )}
      end

      should 'save record on database' do
        assert !subject.new_record?
      end

      should 'save specific content type' do
        assert_equal 'text/css', subject.content_type
      end
    end # with content type specified

    context 'with bad file name' do
      setup do
        login(:ant)
      end
      subject do
        secure!(Document) { Document.create( :parent_id=>nodes_id(:cleanWater),
          :name => 'stupid.jpg',
          :file => uploaded_pdf('water.pdf') ) }
      end

      should 'save with the given name' do
        assert !subject.new_record?
        assert_equal "stupid", subject.name
        assert_equal "stupid", subject.version.title
        assert_equal "stupid.jpg", subject.filename
      end
    end # with bad file name
  end # On create a document


  context 'On reading' do
    setup do
      login(:tiger)
    end

    context 'a document' do
      subject do
        secure!(Document) { Document.find( nodes_id(:water_pdf) ) }
      end

      should 'get filename' do
        assert_equal 'water.pdf', subject.filename
      end

      should 'know if it is an image' do
        assert !subject.image?
      end

      should 'get fullpath' do
        assert_equal 'project/clean/water', subject.fullpath
      end

      should 'get the file size' do
        assert_equal 0, subject.size
      end

      should 'have a version' do
        assert_not_nil subject.version
      end

      should 'have a a version with attachment' do
        assert_not_nil subject.version.attachment
      end
    end # a document

    context 'an image' do
      subject do
        secure!(Document) { Document.find( nodes_id(:bird_jpg) )  }
      end

      should 'know if it is an image' do
        assert subject.image?
      end
    end

  end


  context 'Find by path' do
    setup do
      login(:tiger)
    end

    should 'return correct document' do
      doc = secure!(Document) { Document.find_by_path("/projects/cleanWater/water.pdf") }
      assert_equal "/projects/cleanWater/water.pdf", doc.fullpath
    end
  end




  def get_with_full_path
    login(:tiger)
    doc = secure!(Document) { Document.find_by_path("/projects/cleanWater/water.pdf") }
    assert_kind_of Document, doc
    assert_equal "/projects/cleanWater/water.pdf", doc.fullpath
  end





  def test_change_file
    preserving_files('/test.host/data') do
      login(:tiger)
      doc = secure!(Document) { Document.find(nodes_id(:water_pdf)) }
      assert_equal 29279, doc.version.content.size
      assert_equal file_path(:water_pdf), doc.version.content.filepath
      content_id = doc.version.content.id
      # new redaction in 'en'
      assert doc.update_attributes(:c_file=>uploaded_pdf('forest.pdf'), :v_title=>'forest gump'), "Can change file"
      assert_not_equal content_id, doc.version.content.id
      assert !doc.version.content.new_record?
      doc = secure!(Node) { nodes(:water_pdf) }
      assert_equal 'forest gump', doc.version.title
      assert_equal 'pdf', doc.version.content.ext
      assert_equal 63569, doc.version.content.size
      last_id = Version.find(:first, :order=>"id DESC").id
      assert_not_equal versions_id(:water_pdf_en), last_id
      # filepath is set from initial node name
      assert_equal file_path('water.pdf', 'full', doc.version.content.id), doc.version.content.filepath
      assert doc.update_attributes(:c_file=>uploaded_pdf('water.pdf')), "Can change file"
      doc = secure!(Node) { nodes(:water_pdf) }
      assert_equal 'forest gump', doc.version.title
      assert_equal 'pdf', doc.version.content.ext
      assert_equal 29279, doc.version.content.size
      assert_equal file_path('water.pdf', 'full', doc.version.content.id), doc.version.content.filepath
    end
  end


  def test_create_with_file_name_has_dots
    without_files('/test.host/data') do
      login(:ant)
      doc = secure!(Document) { Document.create( :parent_id=>nodes_id(:cleanWater),
                                                :name=>'report...',
                                                :c_file => uploaded_pdf('water.pdf') ) }
      assert_kind_of Document , doc
      assert ! doc.new_record? , "Not a new record"
      assert_equal "report...", doc.name
      assert_equal "report...", doc.version.title
      assert_equal 'report', doc.version.content.name
      assert_equal "report....pdf", doc.filename
      assert_equal 'pdf', doc.version.content.ext
    end
  end

  def test_create_with_file_name_unknown_ext
    without_files('/test.host/data') do
      login(:ant)
      doc = secure!(Document) { Document.create( :parent_id=>nodes_id(:cleanWater),
                                                :c_file  => uploaded_fixture("some.txt", 'application/octet-stream', "super.zz") ) }
      assert_kind_of Document , doc
      assert ! doc.new_record? , "Not a new record"
      assert_equal "super", doc.name
      assert_equal "super", doc.version.title
      assert_equal 'super', doc.version.content.name
      assert_equal "super.zz", doc.filename
      assert_equal 'zz', doc.version.content.ext
      assert_equal 'application/octet-stream', doc.version.content.content_type
    end
  end

  def test_destroy_many_versions
    preserving_files('/test.host/data') do
      login(:tiger)
      doc = secure!(Node) { nodes(:water_pdf) }
      filepath = doc.version.content.filepath
      assert File.exist?(filepath), "File path #{filepath.inspect} exists"
      first = doc.version.number
      content_id = doc.version.content.id
      assert doc.update_attributes(:v_title => 'WahWah')
      second = doc.version.number
      assert first != second
      assert_equal content_id, doc.version.content.id # shared content
      doc = secure!(Node) { nodes(:water_pdf) }
      doc.version(first)
      assert doc.unpublish
      assert doc.can_destroy_version?
      assert doc.destroy_version
      doc = secure!(Node) { nodes(:water_pdf) }
      assert File.exist?(filepath)
      assert_equal content_id, doc.version.content.id # shared content note destroyed
      assert doc.remove
      assert doc.destroy_version
      assert_nil DocumentContent.find_by_id(content_id)
      assert ! File.exist?(filepath)
    end
  end

  def test_set_v_title
    without_files('/test.host/data') do
      login(:ant)
      doc = secure!(Document) { Document.create( :parent_id=>nodes_id(:cleanWater),
                                                :c_file  => uploaded_fixture('water.pdf', 'application/pdf', 'wat'), :v_title => "lazy waters.pdf") }
      assert_kind_of Document , doc
      assert ! doc.new_record? , "Not a new record"
      assert_equal "lazyWaters", doc.name
      assert_equal "lazy waters", doc.version.title
      assert_equal 'lazyWaters', doc.version.content.name
      assert_equal "lazyWaters.pdf", doc.filename
      assert_equal 'pdf', doc.version.content.ext
      assert_equal 'application/pdf', doc.version.content.content_type
    end
  end

end
