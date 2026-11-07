require "spec_helper"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe ActiveRecordPrettyKey do
  it "has a version number" do
    expect(ActiveRecordPrettyKey::VERSION).not_to be nil
  end

  it "does not load ActiveRecord::Base when the gem is required" do
    script = <<~RUBY
      require "active_record_pretty_key"
      loaded_early = !ActiveRecord.autoload?(:Base) || defined?(ActiveRecordPrettyKey::PrettyKeyTicket)
      ActiveRecord::Base
      print [loaded_early ? "early" : "lazy", defined?(ActiveRecordPrettyKey::PrettyKeyTicket).inspect].join(",")
    RUBY
    lib = File.expand_path("../lib", __dir__)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I#{lib}", "-rbundler/setup", "-e", script)

    expect(status).to be_success, err
    expect(out).to eq('lazy,"constant"')
  end

  describe "Concern" do
    before do
      # Create a posts table with string primary key for testing
      ActiveRecord::Base.connection.create_table :posts, id: :string do |t|
        t.string :title
        t.timestamps
      end
    end

    let(:post_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
        include ActiveRecordPrettyKey::Concern
      end
    end

    it "can be included in a model" do
      expect(post_class.included_modules).to include(ActiveRecordPrettyKey::Concern)
    end

    it "automatically generates SQID on create" do
      post = post_class.create!(title: "Test Post")
      expect(post.id).to be_present
      expect(post.id).to match(/^[a-zA-Z0-9]+$/)
    end

    it "generates unique SQIDs" do
      post1 = post_class.create!(title: "Post 1")
      post2 = post_class.create!(title: "Post 2")
      expect(post1.id).not_to eq(post2.id)
    end

    it "only generates SQID when primary key is string type" do
      ActiveRecord::Base.connection.create_table :comments do |t|
        t.string :content
        t.timestamps
      end

      comment_class = Class.new(ActiveRecord::Base) do
        self.table_name = "comments"
        include ActiveRecordPrettyKey::Concern
      end

      expect(ActiveRecordPrettyKey::PrettyKeyTicket).not_to receive(:next_sqid)
      comment = comment_class.create!(content: "Test Comment")
      expect(comment.id).to be_a(Integer)
    end

    it "doesn't overwrite existing primary key values" do
      existing_id = "existing-123"
      post = post_class.create!(id: existing_id, title: "Test Post")
      expect(post.id).to eq(existing_id)
    end

    describe "#generate_pretty_key" do
      it "can be called publicly and returns the generated key" do
        post = post_class.new(title: "Manual")
        key = post.generate_pretty_key
        expect(key).to be_present
        expect(post.id).to eq(key)

        post.save!
        expect(post.reload.id).to eq(key)
      end

      it "returns the existing key without generating a new one" do
        post = post_class.new(id: "keep-me")
        expect(ActiveRecordPrettyKey::PrettyKeyTicket).not_to receive(:next_sqid)
        expect(post.generate_pretty_key).to eq("keep-me")
      end
    end
  end

  describe "PrettyKeyTicket" do
    let(:ticket) { ActiveRecordPrettyKey::PrettyKeyTicket }

    it "generates unique, increasing integer IDs" do
      id1 = ticket.next_id
      id2 = ticket.next_id
      expect(id1).to be_a(Integer)
      expect(id2).to be_a(Integer)
      expect(id2).to be > id1
    end

    it "generates unique IDs while the query cache is enabled" do
      ids = ActiveRecord::Base.cache { [ ticket.next_id, ticket.next_id ] }
      expect(ids.uniq.size).to eq(2)
    end

    it "generates unique keys for unsaved records while the query cache is enabled" do
      ActiveRecord::Base.connection.create_table :posts, id: :string
      post_class = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
        include ActiveRecordPrettyKey::Concern
      end

      keys = ActiveRecord::Base.cache { [ post_class.new.generate_pretty_key, post_class.new.generate_pretty_key ] }
      expect(keys.uniq.size).to eq(2)
    end

    it "keeps a single row in the tickets table" do
      3.times { ticket.next_id }
      expect(ticket.count).to eq(1)
    end

    it "returns the ID of the replaced ticket row", adapters: %w[sqlite3 mysql2 trilogy] do
      last_id = 3.times.map { ticket.next_id }.last
      expect(ticket.first.id).to eq(last_id)
    end

    it "generates unique IDs across concurrent connections", adapters: %w[postgresql mysql2 trilogy] do
      threads = Array.new(8) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Array.new(25) { ticket.next_id }
          end
        end
      end
      ids = threads.flat_map(&:value)

      expect(ids.size).to eq(200)
      expect(ids.uniq.size).to eq(200)
    end

    it "recreates a missing ticket row safely under concurrency", adapters: %w[mysql2 trilogy] do
      ticket.delete_all
      threads = Array.new(8) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Array.new(10) { ticket.next_id }
          end
        end
      end
      ids = threads.flat_map(&:value)

      expect(ids.uniq.size).to eq(80)
      expect(ticket.count).to eq(1)
    end

    # In-memory SQLite gives each connection its own empty database
    it "does not leave the thread's connection checked out", adapters: %w[postgresql mysql2 trilogy] do
      pool = ActiveRecord::Base.connection_pool
      still_checked_out = Thread.new do
        pool.with_connection { ticket.next_id }
        pool.active_connection?
      end.value

      expect(still_checked_out).to be_falsey
    end

    it "does not block other connections while the caller's transaction is open", adapters: %w[postgresql mysql2 trilogy] do
      pool = ActiveRecord::Base.connection_pool
      ready = Queue.new
      release = Queue.new

      holder = Thread.new do
        pool.with_connection do
          ticket.transaction do
            ticket.next_id
            ready << true
            release.pop
          end
        end
      end
      ready.pop

      other = Thread.new do
        pool.with_connection { ticket.transaction { ticket.next_id } }
      end

      expect(other.join(5)).not_to be_nil, "ticket allocation blocked on the open transaction"
      expect(other.value).to be_a(Integer)
    ensure
      release << true
      holder&.join
      other&.join
    end

    it "never reissues an ID allocated in a transaction that rolled back", adapters: %w[postgresql mysql2 trilogy] do
      issued = nil
      ActiveRecord::Base.transaction do
        issued = ticket.next_id
        raise ActiveRecord::Rollback
      end

      expect(ticket.next_id).to be > issued
    end

    it "never gives a later record the key of a record whose transaction rolled back", adapters: %w[postgresql mysql2 trilogy] do
      ActiveRecord::Base.connection.create_table :posts, id: :string
      post_class = Class.new(ActiveRecord::Base) do
        self.table_name = "posts"
        include ActiveRecordPrettyKey::Concern
      end

      # e.g. the key was sent to a job or API before the transaction rolled back
      leaked_key = nil
      ActiveRecord::Base.transaction do
        leaked_key = post_class.create!.id
        raise ActiveRecord::Rollback
      end

      expect(post_class.create!.id).not_to eq(leaked_key)
    end

    it "allocates MySQL tickets on a dedicated connection pool", adapters: %w[mysql2 trilogy] do
      pool = ticket.ticket_connection_pool
      expect(pool).not_to equal(ActiveRecord::Base.connection_pool)
      expect(ticket.ticket_connection_pool).to equal(pool)
      expect(pool.db_config.configuration_hash).to eq(ActiveRecord::Base.connection_db_config.configuration_hash)
    end

    it "generates SQIDs from IDs" do
      sqid = ticket.next_sqid
      expect(sqid).to be_a(String)
      expect(sqid).to match(/^[a-zA-Z0-9]+$/)
      expect(sqid.length).to be >= ActiveRecordPrettyKey::PrettyKeyTicket::MIN_LENGTH
    end

    it "generates different SQIDs on each call" do
      sqid1 = ticket.next_sqid
      sqid2 = ticket.next_sqid
      expect(sqid1).not_to eq(sqid2)
    end

    it "works when the table has no ticket row, as after db:schema:load" do
      ticket.delete_all
      ids = Array.new(3) { ticket.next_id }
      expect(ids).to eq(ids.sort)
      expect(ids.uniq.size).to eq(3)
    end

    it "keeps issuing larger IDs if the ticket row is deleted", adapters: %w[postgresql mysql2 trilogy] do
      before = Array.new(3) { ticket.next_id }.last
      ticket.delete_all
      expect(ticket.next_id).to be > before
    end

    it "raises a clear error for unsupported database adapters" do
      allow(ticket.connection).to receive(:adapter_name).and_return("Oracle")
      expect { ticket.next_id }.to raise_error(ActiveRecordPrettyKey::Error, /Unsupported database adapter "Oracle"/)
    end

    describe "alphabet" do
      let(:custom_alphabet) { Sqids::DEFAULT_ALPHABET.chars.reverse.join }

      it "uses the default alphabet outside of Rails" do
        hide_const("Rails")
        expect(ticket.alphabet).to eq(Sqids::DEFAULT_ALPHABET)
      end

      it "reads a custom alphabet from Rails credentials when first used" do
        credentials = { sqids: { alphabet: custom_alphabet } }
        stub_const("Rails", double(application: double(credentials: credentials)))
        allow(ticket).to receive(:next_id).and_return(42)

        sqid = ticket.next_sqid
        expect(ticket.alphabet).to eq(custom_alphabet)
        expect(Sqids.new(alphabet: custom_alphabet, min_length: 4).decode(sqid)).to eq([ 42 ])
        expect(Sqids.new(min_length: 4).decode(sqid)).not_to eq([ 42 ])
      end

      it "falls back to the default alphabet before Rails.application exists" do
        stub_const("Rails", double(application: nil))
        expect(ticket.alphabet).to eq(Sqids::DEFAULT_ALPHABET)
      end
    end
  end

  describe "install generator" do
    require "generators/active_record_pretty_key/install/install_generator"

    around do |example|
      Dir.mktmpdir { |dir| @destination = dir; example.run }
    end

    def run_generator
      ActiveRecordPrettyKey::Generators::InstallGenerator.start(["--quiet"], destination_root: @destination)
      Dir[File.join(@destination, "db/migrate/*.rb")]
    end

    it "creates a single timestamped migration" do
      files = run_generator
      expect(files.size).to eq(1)
      expect(File.basename(files.first)).to match(/\A\d{14}_create_pretty_key_tickets\.rb\z/)
    end

    it "creates a migration that sets up the tickets table and can be rolled back" do
      connection = ActiveRecord::Base.connection
      connection.drop_table(:pretty_key_tickets)

      load run_generator.first
      migration = CreatePrettyKeyTickets.new
      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }

      expect(connection.table_exists?(:pretty_key_tickets)).to be true
      expect(ActiveRecordPrettyKey::PrettyKeyTicket.count).to eq(1)
      expect(ActiveRecordPrettyKey::PrettyKeyTicket.next_id).to be_a(Integer)

      ActiveRecord::Migration.suppress_messages { migration.migrate(:down) }
      expect(connection.table_exists?(:pretty_key_tickets)).to be false
    ensure
      Object.send(:remove_const, :CreatePrettyKeyTickets) if defined?(CreatePrettyKeyTickets)
    end
  end
end
