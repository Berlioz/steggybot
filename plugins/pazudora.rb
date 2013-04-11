require 'cinch'
require 'nokogiri'
require 'pry'

class Pazudora
  include Cinch::Plugin
  
  PUZZLEMON_BASE_URL = "http://www.puzzledragonx.com/en/"
  
  match /pazudora ([\w-]+) *(.+)*/i, method: :pazudora
  match /stupidpuzzledragonbullshit ([\w-]+) *(.+)*/i, method: :pazudora
  match /stupiddragonpuzzlebullshit ([\w-]+) *(.+)*/i, method: :pazudora
  match /p&d ([\w-]+) *(.+)*/i, method: :pazudora
  match /pad ([\w-]+) *(.+)*/i, method: :pazudora
  match /puzzlemon ([\w-]+) *(.+)*/i, method: :pazudora
  match /puzzledex (.+)*/i, method: :pazudora_lookup
  
  @help_string = <<-eos
  Puzzle and Dragons (on iOS and Android) utility functions. Mostly collects friend codes and tracks the daily dungeon.
  Its commands are aliased to pazudora, p&d, pad,  and puzzlemon.
  eos
  @help_hash = {
    :add => "Usage: !puzzlemon add NAME CODE
Example: !puzzlemon add steggybot 123,456,789
Adds user's code to the list of friend codes",
    :group => "Usage: !puzzlemon group NAME
Example !puzzlemon group steggybot
Returns the daily dungeon group that the user belongs to.",
    :dailies => "Usage: !puzzlemon dailies
Example !puzzlemon dailies
Returns the times (and type) of today's daily dungeons, split by group. If called by
a registered player, also reminds them of their group id.",
    :lookup => "Usage: !(puzzlemon lookup|puzzledex) (NAME|ID)
Example !puzzlemon lookup horus, !puzzledex 603
Returns a description of the puzzlemon. If none is found, returns a pseudorandom (hashed) one.",
    :list => "Usage: !puzzlemon list
Example !puzzlemon list
Returns a list of everyone's friends codes.",
    :evolution => "Usage: !puzzlemon evolution
Example !puzzlemon siren evolution
Returns the set of evo materials necessary to advance to the next tier",
    :experience => "Usage: !puzzlemon experience [TO] [FROM]
Example !puzzlemon siren 24 30
Calculates the amount of experience required to advance from TO to FROM.
TO defaults to 1, FROM defaults to the maximum level of the puzzlemon.
YES I KNOW THERE ARE NO LIGHT/DARK PENGDRAS A BLOO BLOOO"
  }
  
  def initialize(*args)
    super
    @pddata = config[:pddata]
  end
  
  #Any public method named pazudora_[something] is external and
  #can be accessed by the user using the construction "!puzzlemon something [args]".
  def pazudora (m, cmd, args)
    subr = cmd.downcase.chomp
    begin
      if args
        self.send("pazudora_#{subr}", m, args)
      else
        self.send("pazudora_#{subr}", m, "")
      end
    rescue NoMethodError
      puts "Pazudora called with invalid command #{subr}."
      raise
    end
  end
  
  def pazudora_add (m, args)
    pargs = args.split
    username = pargs[0]
    friend_code = pargs[1]
    
    # add it to the list
    friend_codes = load_data || {}
    if friend_code =~ /[0-9]{9}/
      friend_code = friend_code.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end 
    if friend_codes[username.downcase] && (friend_codes[username.downcase][:added_by] == username.downcase)
      if m.user.nick.downcase == username.downcase
        friend_codes[username.downcase] = {:friend_code => friend_code, :added_by => m.user.nick.downcase, :updated_at => DateTime.now}
      else
        m.reply "#{m.user.nick}: Can't override a user's self-definition."
        return
      end
    else
      friend_codes[username.downcase] = {:friend_code => friend_code, :added_by => m.user.nick.downcase, :updated_at => DateTime.now}
    end
    # write it to the file
    output = File.new(@pddata, 'w')
    output.puts YAML.dump(friend_codes)
    output.close
      
    m.reply "#{m.user.nick}: #{mangle(username)} successfully added as '#{friend_code}'."
  end
  
  def pazudora_remove(m, args)
    pargs = args.split
    username = pargs[0]
    friend_codes = load_data || {}
    
    if ! friend_codes[username]
      m.reply "#{m.user.nick}: #{mangle(username)} not in friend code list."
      return
    end
    
    if (m.user.nick.downcase == username.downcase) || (m.user.nick.downcase == friend_codes[username][:added_by])
      friend_codes.delete(username)
      # write it to the file
      output = File.new(@pddata, 'w')
      output.puts YAML.dump(friend_codes)
      output.close
      
      m.reply "#{m.user.nick}: #{mangle(username)} removed from friend code list."
    else
      m.reply "#{m.user.nick}: Only the identity creator or subject can remove a friend code from the list."
    end
  end
  
  def pazudora_who(m,args)
    pargs = args.split
    username = pargs[0]
    if load_data[username.downcase]
      m.reply "#{m.user.nick}: #{mangle(username)}'s friend code is #{load_data[username.downcase][:friend_code]}"
    end
  end
  
  def pazudora_list(m,args)
    friend_codes = load_data || {}
    friend_codes.keys.each_slice(3).with_index { |users, i| 
      r = i == 0 ? "#{m.user.nick}: " : ""
      users.each{ |user| r=r+"#{mangle(user)}:#{friend_codes[user][:friend_code]} " }
      m.reply r
    }
  end
  
  def pazudora_group(m,args)
    pargs = args.split
    username = pargs[0]
    if load_data[username.downcase]
      friend_code = load_data[username.downcase][:friend_code]
      group = (Integer(friend_code.split(",")[0][2]) % 5 + 65).chr
      m.reply "#{m.user.nick}: #{mangle(username)}'s group is #{group}"
    else
      m.reply "#{m.user.nick}: #{mangle(username)}'s friend code is not listed. Please use the add command to add it."
    end
  end
  
  def pazudora_dailies(m, args)
    daily_url = PUZZLEMON_BASE_URL + "option.asp?utc=-8"
    
    username = args.split[0] || m.user.nick
    friend_code = load_data[username.downcase][:friend_code] rescue nil
    group_num = friend_code ? group_number_from_friend_code(friend_code) : nil
    
    unless @daily_timestamp == Time.now.strftime("%m-%d-%y")
      @daily_page = nil
      @daily_timestamp = Time.now.strftime("%m-%d-%y")
    end
    
    @daily_page ||= Nokogiri::HTML(open(daily_url))
    event_data = @daily_page.css(".event3")
    event_rewards = @daily_page.css(".limiteddragon")
    
    rewards = parse_daily_dungeon_rewards(event_rewards)
    m.reply "Dungeons today are: #{rewards.join(', ')}"
    
    (0..4).each do |i|
      m.reply "Group #{(i + 65).chr}: #{event_data[i].text}, #{event_data[i + 5].text}, #{event_data[i + 10].text}"
    end
    
    if group_num
      m.reply "User #{username} is in group #{(group_num + 65).chr}"
    end
  end
  
  def pazudora_lookup(m, args)
    identifier = args
    info = pdx_page_from_identifier(identifier)
		m.reply "Unknown puzzlemon #{identifier}" and return unless info
    
    desc = info.css("meta [name=description]").first.attributes["content"].text
    desc.gsub!(/&amp;/, "&")
    m.reply desc
  end

  def pazudora_chain(m, args)
    identifier = args
    info = pdx_page_from_identifier(identifier)
		m.reply "Unknown puzzlemon #{identifier}" and return unless info

    puzzlemon_id = id_from_nokogiri(info)

		# Compute the ID numbers of the puzzlemons in this particular chain
    chain_divs = info.xpath("//td[@class='evolve']//div[@class='eframenum']")
		chain_members = chain_divs.map{|div| name_from_id(div.children.first.text)}
		# Check whether there is a multi-choice ultimate evolution
		ultimate_count = info.xpath("//td[@class='finalevolve']").length
		if ultimate_count > 1
      ((-1 * ultimate_count)..-1).step do |n|
        chain_members[n] = "\t#{chain_members[n]} (busty)"
      end
    end

    name = name_from_nokogiri(info)
		r = "Puzzlemon #{name}'s evolution chain:\n" + chain_members.join("\n")
    m.reply r    
  end

  def pazudora_evolution(m, args)
    identifier = args
    info = pdx_page_from_identifier(identifier)
		m.reply "Unknown puzzlemon #{identifier}" and return unless info

    puzzlemon_id = id_from_nokogiri(info)
    name = name_from_nokogiri(info)

		# Compute the ID numbers of the puzzlemons in this particular chain
    chain_divs = info.xpath("//td[@class='evolve']//div[@class='eframenum']")
		chain_members = chain_divs.map{|div| div.children.first.to_s}

    # Compute the location of the current puzzlemon in the chain
    requirements = info.xpath("//td[@class='require']")
    busty_requirements = info.xpath("//td[@class='finalevolve']")
    ultimate_count = busty_requirements.count
		index = chain_members.index(puzzlemon_id)

    p requirements.count
    p busty_requirements.count
    p ultimate_count
    p index

    if index == requirements.length && ultimate_count > 0
      r = "Puzzlemon #{name} busty evolution materials:\n" +
          busty_requirements.
						map{|r| evo_material_list(r).join("\n")}.
						join("\n\t-or-\t\n")
    elsif index >= requirements.length
      r = "Puzzlemon #{name} appears to be at the end of its chain."
    else
      r = "Puzzlemon #{name} evolution materials:\n" + 
					evo_material_list(requirements[index]).join("\n") 
    end
    m.reply r
  end

  def pazudora_experience(m, args)
    argv = args.split(" ")
    tail = []

    2.times do
			if is_numeric?(argv.last)
	      tail << argv.pop.to_i
	    end
    end

    identifier = argv.join(" ")
    info = pdx_page_from_identifier(identifier)
		m.reply "Unknown puzzlemon #{identifier}" and return unless info

    if tail.length == 0
      from = 1
      to = max_level(info)
    elsif tail.length == 1
      from = tail[0]
      to = max_level(info)
    else
      to = tail[0]
      from = tail[1]
    end

    links = info.xpath("//a").map{|element| element.attributes["href"]}.compact
    curve_link = links.select{|link| link.value.include?("experiencechart")}.first
    curve_page = Nokogiri::HTML(open(PUZZLEMON_BASE_URL + curve_link.value))
    begin
      delta = xp_at_level(curve_page, to) - xp_at_level(curve_page, from)
    rescue NoMethodError
      r = "Bad level thresholds #{from} - #{to}"
      m.reply(r) and return
    end
    pengies = delta.to_f / (45000.0)
    pengies = pengies.round(2)
    r = "Getting puzzlemon #{name_from_nokogori(info)} from #{from} to #{to} 
takes #{delta} xp, or #{pengies} pengdras. Get farming!"
    m.reply r    
  end
  
  protected
  # duh
	def is_numeric?(str)
	  begin
	    !!Integer(str)
	  rescue ArgumentError, TypeError
	    false
	  end
	end

	# given an id or monster name, uses pdx's fuzzy matcher to find the pdx
  # page for the referenced monster. Returns nil if the fuzzy matcher returns
  # nothing e.g meteor dragon what the fuck seriously jesus christ
  def pdx_page_from_identifier(identifier)
		info = get_puzzlemon_info(URI.encode(identifier))
    
    #Bypass puzzledragonx's "default to meteor dragon if you can't find the puzzlemon" mechanism
    meteor_dragon_id = "211"

    if info.css(".name").children.first.text == "Meteor Volcano Dragon" && !(identifier.start_with?("Meteor") || identifier == meteor_dragon_id)
      return nil
    else
      return info
    end
  end

	# turn an identifier, numeric or otherwise, into the true name of a monster
  def name_from_id(id)
		name_from_nokogiri(pdx_page_from_identifier(id))
  end

	# grab the name of a monster from its page the stupid way
  def name_from_nokogiri(doc)
		doc.css(".name").children.first.text
  end

  # find the URL of the image of the monster, and parse it for the monster's id
  def id_from_nokogiri(doc)
    avatar_image = doc.xpath("//div[@class='avatar']").first.children.first
    path = avatar_image.attributes["src"].value
    /img\/book\/(\d+)\.png/.match(path)[1]
  end

  # convert a requirements td into a list of evolution materials
  def evo_material_list(td)
    material_elements = td.children.select{|element| element.name == "a"}
    material_elements.map do |element|
      element.children.first.attributes["title"].value
    end
  end

  # given an XP curve page, return the XP required to hit a level from 0
  def xp_at_level(doc, level)
    all_elements = doc.xpath("//table[@id='tablechart']//tbody//td")
    rows = doc.xpath("//table[@id='tablechart']//tbody//td[@class='blue']")
    row_index = all_elements.index(rows.select{|h| h.text == level.to_s}.first)
    all_elements[row_index + 1].text.to_i
  end

  # given a pazudora info page, find the max level of the monster
  def max_level(doc)
    level_row = doc.xpath("//table[@id = 'tablestat']//td[@class = 'title']").
			select{|x| x.text == "Level:"}.first
		siblings = level_row.parent.children
    siblings[2].text.to_i
  end

  def mangle(s)
    s.chop + "." + s[-1]
  end
  
  def load_data
    datafile = File.new(@pddata, 'r')
    friend_codes = YAML.load(datafile.read)
    datafile.close
    return friend_codes
  end
  
  def group_number_from_friend_code(friend_code)
    return Integer(friend_code.split(",")[0][2]) % 5
  end
  
  def parse_daily_dungeon_rewards(rewards)
    puzzlemon_numbers = [
    rewards[0].children.first.attributes["src"].value.match(/thumbnail\/(\d+).png/)[1],
    rewards[5].children.first.attributes["src"].value.match(/thumbnail\/(\d+).png/)[1],
    rewards[10].children.first.attributes["src"].value.match(/thumbnail\/(\d+).png/)[1]]
    
    puzzlemon_numbers.map{|x| 
      get_puzzlemon_info(x).css(".name").children.first.text rescue "Unrecognized Name" }
  end
  
  def get_puzzlemon_info(name_or_number)
    search_url = PUZZLEMON_BASE_URL + "monster.asp?n=#{name_or_number}"
    puzzlemon_info = Nokogiri::HTML(open(search_url))
  end
end


