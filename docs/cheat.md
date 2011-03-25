# Bud Cheat Sheet #

## General Bloom Syntax Rules ##
Bloom programs are unordered sets of statements.<br>
Statements are delimited by semicolons (;) or newlines. <br>
As in Ruby, backslash is used to escape a newline.<br>

## Simple embedding of Bud in a Ruby Class ##
    require 'bud'

    class Foo
        include Bud
        
        state do
          ...
        end
        
        bloom do
          ...
        end
    end
    
## State Declarations ##
Use `state` to register a Ruby block of state declarations to be invoked during Bud bootstrapping.

### Default Declaration Syntax ###
*BudCollection :name, [keys] => [values]*

### table ###
contents persist in memory until deleted.<br>
default attributes: `[:key] => [:val]`

    table :keyvalue
    table :composite, [:keyfield1, :keyfield2] => [:values]
    table :noDups, [:field1, field2]

### scratch ###
contents emptied at start of each timestep<br>
default attributes: `[:key] => [:val]`

    scratch :stats

### interface ###
scratch collections, used as module interfaces<br>
default attributes: `[:key] => [:val]`

    interface input, :request
    interface output, :response

### channel ###
network channel manifested as a scratch collection.  <br>
address attribute prefixed with `@`.  <br>
default attributes: `[:@address, :val] => []`

(bloom statements with channel on lhs must use async merge (`<~`).)


    channel :msgs
    channel :req_chan, [:@address, :cartnum, :storenum] => [:command, :params]


### periodic ###
system timer manifested as a scratch collection.<br>
system-provided attributes: `[:key] => [:val]`<br>
&nbsp;&nbsp;&nbsp;&nbsp; (key is a unique ID, val is a Ruby Time converted to a string.)<br>
state declaration includes interval (in seconds)

(periodic can only be used on rhs of a bloom statement)

    periodic :timer, 0.1

### stdio ###
built-in scratch collection mapped to Ruby's `$stdin` and `$stdout`<br>
system-provided attributes: `[:line] => []`

(statements with stdio on lhs must use async merge (`<~`)<br>
to capture `$stdin` on rhs, instantiate Bud with `:read_stdin` option.)<br>

### tctable ###
table collection mapped to a [Tokyo Cabinet](http://fallabs.com/tokyocabinet/) store.<br>
default attributes: `[:key] => [:val]`

    tctable :t1
    tctable :t2, [:k1, :k2] => [:v1, :v2]

### zktable ###
table collection mapped to an [Apache Zookeeper](http://hadoop.apache.org/zookeeper/) store.<br>
given attributes: `[:key] => [:val]`<br>
state declaration includes zookeeper path
and optional TCP string (default: "localhost:2181")<br>

    zktable :foo, "/bat"
    zktable :bar, "/dat", "localhost:2182"


## Bloom Statements ##
*lhs BloomOp rhs*

Left-hand-side (lhs) is a named `BudCollection` object.<br>
Right-hand-side (rhs) is a Ruby expression producing a `BudCollection` or `Array` of `Arrays`.<br>
BloomOp is one of the 5 operators listed below.

## Bloom Operators ##
merges:

* `left <= right` &nbsp;&nbsp;&nbsp;&nbsp; (*instantaneous*)
* `left <+ right` &nbsp;&nbsp;&nbsp;&nbsp; (*deferred*)
* `left <~ right` &nbsp;&nbsp;&nbsp;&nbsp; (*asynchronous*)

delete:

* `left <- right` &nbsp;&nbsp;&nbsp;&nbsp; (*deferred*)

insert:<br>
unlike merge/delete, insert expects a singly-nested array on the rhs

* `left << [...]` &nbsp;&nbsp;&nbsp;&nbsp; (*instantaneous*)


## Collection Methods ##
Standard Ruby methods used on a BudCollection `bc`:

implicit map:

    t1 <= bc {|t| [t.col1 + 4, t.col2.chomp]} # formatting/projection
    t2 <= bc {|t| t if t.col = 5}             # selection
    
`flat_map`:

    require 'backports' # flat_map not included in Ruby 1.8 by default

    t3 <= bc.flat_map do |t| # unnest a collection-valued attribute
      bc.col4.map { |sub| [t.col1, t.col2, t.col3, sub] }
    end

`bc.reduce`, `bc.inject`:

    t4 <= bc.reduce({}) do |memo, t|  # example: groupby col1 and count
      memo[t.col1] ||= 0
      memo[t.col1] += 1
      memo
    end

`bc.include?`:

    t5 <= bc do |t| # like SQL's NOT IN
        t unless t2.include?([t.col1, t.col2])
    end

## BudCollection-Specific Methods ##
`bc.keys`: projects `bc` to key columns<br>

`bc.values`: projects `bc` to non-key columns<br>

`bc.inspected`: shorthand for `bc {|t| [t.inspect]}`

    stdio <~ bc.inspected

`chan.payloads`: shorthand for `chan {|t| t.val}`, only defined for channels

    # at sender
    msgs <~ requests {|r| "127.0.0.1:12345", r}
    # at receiver
    requests <= msgs.payloads

`bc.exists?`: test for non-empty collection.  Can optionally pass in a block.

    stdio <~ [["Wake Up!"] if timer.exists?]
    stdio <~ requests do |r|
      [r.inspect] if msgs.exists?{|m| r.ident == m.ident}
    end

## SQL-style grouping/aggregation (and then some) ##

* `bc.group([:col1, :col2], min(:col3))`.  *akin to min(col3) GROUP BY (col1,col2)*
  * exemplary aggs: `min`, `max`, `choose`
  * summary aggs: `sum`, `avg`, `count`
  * structural aggs: `accum`
* `bc.argmax([:col1], :col2)` &nbsp;&nbsp;&nbsp;&nbsp; *returns the bc tuple per col1 that has highest col2*
* `bc.argmin([:col1], :col2)`

## Built-in Aggregates: ##

* Exemplary aggs: `min`, `max`, `choose`
* Summary aggs: `count`, `sum`, `avg`
* Structural aggs: `accum`

## Join, Coincide ###
`join` and `coincide` are synonyms.<br>
First argument is always an array of collections to join.<br>
Later arguments are arrays of columns to be matched (equijoin).

`join([`*tablelist*`]` *,[optional column matches], ...*`)`<br>
`coincide([`*tablelist*`]` *,[optional column matches], ...*`)`<br>

    # the following 3 Bloom statements are equivalent to this SQL
    # SELECT r.a, s_tab.b, t.c
    #   FROM r, s_tab, t
    #  WHERE r.x = s_tab.x
    #    AND s_tab.x = t.x;

    # multiple column matches
    out <= join([r,s_tab,t],
                [r.x, s_tab.x], [s_tab.x, t.x]) do |t1, t2, t3|
             [t1.a, t2.b, t3.c]
           end

    # a single 3-way column match
    out <= join([r,s_tab,t], [r.x, s_tab.x, t.x]) do |t1, t2, t3|
             [t1.a, t2.b, t3.c]
           end

    # column matching done per pair: this will be very slow
    out <= join([r,s_tab,t]) do |t1, t2, t3|
             [t1.a, t2.b, t3.c] if r.x == s_tab.x and s_tab.x = t.x
           end

    # coincide is a more natural verb for timers and messages.
    # here is a typical timeout/retry pattern for requests
    request_chan <~ coincide([request_buf, timeout]) {|r, t| r }

`natjoin([`*tablelist*`]`)<br>
Natural join of tables.
Implicitly includes matching of attributes across collections with the same name.<br>
The following is equivalent to the above statements if `x` is the only attribute name in common:

    out <= natjoin([r, s_tab, t]) do {|t1, t2, t3| [t1.a, t2.b, t3.c]}

`leftjoin([`*t1, t2*`]` *, [optional column matches], ...*`)`<br>
Left Outer Join.  Objects in the first collection will be included in the output even if no match is found in the second collection.

### Join methods ###
`join([`*tablelist*`]` *,[optional column matches], ...*`).flatten`<br>
`flatten` is a bit like SQL's `SELECT *`: it produces a collection of concatenated objects, with a schema that is the concatenation of the schemas in tablelist (with duplicate names disambiguated.) Useful for chaining to operators that expect input collections with schemas, e.g. group:

    out <= natjoin([r,s]).flatten.group([:a], max(:b))

## Temp/Equality statements ##
`temp`<br>
temp collections are scratches defined within a Bloom block:

    temp :my_scratch1 <= foo

The schema of a temp collection in inherited from the rhs; if the rhs has no schema, a simple one is manufactured to suit the data in the rhs at runtime: [c0, c1, ...].


## Interacting with Bud from Ruby ##
* `run`
* `run_bg`
* `sync_do`
* `async_do`
* callbacks

## Bud Code Visualizer ##



## Skeleton of a Bud Module ##

    require 'rubygems'
    require 'bud'

    module YourModule
      include Bud

      state do
        ...
      end

      bootstrap do
        ...
      end

      bloom :some_stmts do
        ...
      end

      bloom :more_stmts do
        ...
      end
    end
