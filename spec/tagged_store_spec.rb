require "active_support"

describe "TaggedStore" do
  before(:each) do
    @options = { tag_store: [:memory_store, { namespace: "tags" }], entity_store: [:memory_store, { namespace: "entities" }] }
  end

  context "without :tag_store option" do
    subject { -> { ActiveSupport::Cache.lookup_store :tagged_store, @options.delete(:tag_store) } }
    it { should raise_exception }
  end

  context "without :entity_store option" do
    subject { -> { ActiveSupport::Cache.lookup_store :tagged_store, @options.delete(:entity_store) } }
    it { should raise_exception }
  end

  context "with :tag_store and :entity_store options" do
    subject { -> { ActiveSupport::Cache.lookup_store :tagged_store, @options } }
    it { should_not raise_exception }
  end

  context "instance" do
    before(:each) do
      @store ||= ActiveSupport::Cache.lookup_store :tagged_store, @options
      @store.clear
    end

    context "#read_tag('abc')" do
      subject  { @store.read_tag("abc") }

      it { should_not be_nil }
      it "should be less or equal Time.now.to_i" do
        should <= Time.now.to_i
      end
    end

    context "#touch_tag('abc')" do
      it "should increment tag value" do
        old_value = @store.read_tag("abc")
        @store.touch_tag("abc")
        expect(@store.read_tag("abc")).to be > old_value
      end
    end

    context "#read_tags('tag1', 'tag2')" do
      before(:each) do
        @tag1_value = @store.read_tag("tag1")
        @tag2_value = @store.read_tag("tag2")

        @tags = @store.read_tags("tag1", "tag2")
      end

      specify { expect(@tags).to have_key("tag1") }
      specify { expect(@tags).to have_key("tag2") }

      it "should return tag1's value" do
        expect(@tags["tag1"]).to eq(@tag1_value)
      end

      it "should return tag2's value" do
        expect(@tags["tag2"]).to eq(@tag2_value)
      end

      ["tag1", "tag2"].each do |tag_name|
        context "#{tag_name}" do
          subject { @tags[tag_name] }
          it { should be_is_a(Integer) }
        end
      end
    end

    context "#read_tags('tagA', 'tagB')" do
      context "when 'tagA' and 'tagB' don't exist in cache" do
        before(:each) do
          @tags = @store.read_tags("tagA", "tagB")
        end

        ["tagA", "tagB"].each do |tag_name|
          context tag_name do
            subject { @tags[tag_name] }
            it { should_not be_nil }
            it { should be_is_a(Integer) }
          end
        end
      end
    end

    context "#clear" do
      before(:each) do
        @tag_abc_value = @store.read_tag("abc")
        @store.write("abc_entity", "test")
        sleep 0.1
        @store.clear
      end

      it "should clear store of entities" do
        expect(@store.read("abc_entity")).to be_nil
      end

      it "should not touch any tags" do
        expect(@store.read_tag("abc")).to eq(@tag_abc_value)
      end
    end

    context "entity" do
      before(:each) do
        @store.write("abc", "test", depends: ["tag1", "tag2"])
      end

      it "should be read from cache when tags are untouched" do
        expect(@store.read("abc")).to eq("test")
      end

      ["tag1", "tag2"].each do |tag_name|
        it "should not be read from cache when '#{tag_name}' is touched" do
          @store.touch_tag(tag_name)
          expect(@store.read("abc")).to be_nil
        end
      end
    end

    context "#fetch('abc', ...)" do
      before(:each) do
        @depends = ["tag1", "tag2"]
        @store.write("abc", true, depends: @depends)
      end

      it "should fetch value from cache when tags are untouched" do
        expect(@store.fetch("abc", depends: @depends) { false }).to be true
      end

      ["tag1", "tag2"].each do |tag_name|
        it "should fetch value from proc when '#{tag_name}' is touched" do
          @store.touch_tag(tag_name)
          expect(@store.fetch("abc", depends: @depends) { false }).to be false
        end
      end
    end

    context "#tagged_fetch('abc', ...)" do
      before(:each) do
        @depends = ["tag1", "tag2"]
        @store.tagged_fetch("abc") do |entry|
          "value".tap do
            entry.depends "tag1"
            entry << "tag2"
            entry.concat "tag1", "tag2"
            entry.concat ["tag1", "tag2"]
          end
        end
      end

      it "should fetch value from cache when tags are untouched" do
        expect(@store.read("abc")).to eq("value")
      end

      ["tag1", "tag2"].each do |tag_name|
        it "should fetch value from proc when '#{tag_name}' is touched" do
          @store.touch_tag(tag_name)
          expect(@store.read("abc")).to be_nil
        end
      end
    end

    context "#touch_tag(object)" do
      before(:each) do
        @tag_value = @store.read_tag("tag1")
      end

      it "should calculate tag name and increment it" do
        obj = Object.new
        module ObjectCacheTag
          def cache_tag
            "tag1"
          end
        end
        obj.extend(ObjectCacheTag)
        @store.touch_tag(obj)
        expect(@store.read_tag("tag1")).to be > @tag_value
      end
    end
  end
end
