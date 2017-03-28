module vision.literal.json;

import pegged.grammar;

mixin(grammar(`
JSON:
    Value  <  String
            / Number
            / JSONObject
            / Array
            / True
            / False
            / Null
            
    JSONObject <  :'{' (Pair (:',' Pair)*)? :'}'
    Pair       <  String :':' Value
    Array      <  :'[' (Value (:',' Value)* )? :']'

    True   <- "true"
    False  <- "false"
    Null   <- "null"

    String <~ :doublequote Char* :doublequote
    Char   <~ backslash doublequote
            / backslash backslash
            / backslash [bfnrt]
            / backslash 'u' Hex Hex Hex Hex
            / (!doublequote .)

    Number <~ '0'
            / [1-9] Digit* ('.' Digit*)?
    Digit  <- [0-9]
    Hex    <- [0-9A-Fa-f]
`));


template json(string literal)
{
	static assert(JSON(literal).successful, "Incorrect json string: "~literal);
	enum json=literal;
}


unittest
{
	assert(__traits(compiles, json!`{"a":1, "b":"c"}`)); 
	assert(__traits(compiles, json!`[1,2,3]`)); 
	assert(__traits(compiles, json!`123`)); 
	assert(__traits(compiles, json!`123.45`)); 
	assert(__traits(compiles, json!`"foo"`)); 

	assert(!__traits(compiles, json!`[1,2,3,]]`)); 
	assert(!__traits(compiles, json!`"foo`)); 
	assert(!__traits(compiles, json!`[1,2`)); 
}