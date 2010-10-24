module Text.Jasmine.Token
    (
    --  TokenParser
      identifier  
    , reserved  
    , whiteSpace  
    , decimal  
    , hexadecimal  
    , autoSemi  
    , autoSemi'  
    , rOp  
    , newJSPState  
    ) where

-- ---------------------------------------------------------------------

import Text.ParserCombinators.Parsec hiding (Line)
import Data.Char ( toLower, isSpace, digitToInt )
import Data.List ( nub, sort )

-- ---------------------------------------------------------------------
-- This bit from HJS Prim.hs

data JSPState = JSPState {nlFlag::Bool}

newJSPState = JSPState { nlFlag = False }

clearNLFlag :: GenParser tok JSPState ()
clearNLFlag = updateState (\x -> x { nlFlag=False })

setNLFlag :: GenParser tok JSPState ()
setNLFlag   = updateState (\x -> x { nlFlag=True })

getNLFlag :: GenParser tok JSPState Bool
getNLFlag   = do s <- getState; return $ nlFlag s                   

-- ---------------------------------------------------------------------

-- Do not use the lexer, it is greedy and consumes subsequent symbols, 
--   e.g. "!" in a==!b
--rOp :: [Char] -> GenParser Char st ()
rOp x = try(rOp'' x)

--rOp'' :: [Char] -> CharParser st ()
rOp'' []     = fail "trying to parse empty token"
rOp'' [x]    = do{ _ <- char x; optional whiteSpace; return () }
rOp'' (x:xs) = do{ _ <- char x; rOp xs;}
                 
-- ---------------------------------------------------------------------

-- Need to deal with the following cases
-- 1. Missing semi, because following } => empty
-- 2. Additional semi, with following } => empty
-- 3. semi with no following }          => semi

-- TODO: change the return to [JSNode], and get rid of the empty JSLiteral
--autoSemi :: GenParser Char st String
autoSemi = try (do { rOp ";"; lookAhead (rOp "}");
                     return ("");})
           <|> try (do{ rOp ";"; 
                        return (";");})
           <|> try (do {lookAhead (rOp "}");
                        return ("");})

--autoSemi' :: GenParser Char st String
autoSemi' = try (do { rOp ";"; lookAhead (rOp "}");
                     return ("");})
           <|> try (do{ rOp ";"; 
                        return (";");})

-- ---------------------------------------------------------------------

{-
lexer :: P.TokenParser st
lexer = P.makeTokenParser javascriptDef
-}      

--identifier :: CharParser st String
--identifier = lexeme $ many1 (letter <|> oneOf "_")
identifier =
        lexeme $ try $
        do{ name <- ident
          ; if (isReservedName name)
             then unexpected ("reserved word " ++ show name)
             else return name
          }

--ident :: GenParser Char st [Char]
ident
        = do{ c <- identStart
            ; cs <- many identLetter
            ; return (c:cs)
            }
        <?> "identifier"

isReservedName :: [Char] -> Bool
isReservedName name
        = isReserved theReservedNames caseName
        where
          caseName      | caseSensitive  = name
                        | otherwise      = map toLower name


isReserved :: (Ord t) => [t] -> t -> Bool
isReserved names name
        = scan names
        where
          scan []       = False
          scan (r:rs)   = case (compare r name) of
                            LT  -> scan rs
                            EQ  -> True
                            GT  -> False

theReservedNames :: [[Char]]
theReservedNames
        | caseSensitive = sortedNames
        | otherwise     = map (map toLower) sortedNames
        where
          sortedNames   = sort reservedNames


--reserved :: String -> CharParser st ()
reserved name =
        lexeme $ try $
        do{ string name
          ; notFollowedBy identLetter <?> ("end of " ++ show name)
          }

--whiteSpace :: CharParser st ()
--whiteSpace = skipMany (simpleSpace <|> oneLineComment <|> multiLineComment <?> "")
whiteSpace = skipMany (simpleSpace <|> oneLineComment <|> multiLineComment <|> do { char '\n'; setNLFlag} <?> "")
-- whiteSpace = try $ many $ (do { equal TokenWhite } <|> do { (equal TokenNL); setNLFlag})


--simpleSpace :: GenParser Char st ()
--simpleSpace = skipMany1 (satisfy isSpace)
simpleSpace  = skipMany1 (satisfy (\c -> isSpace c && c /= '\n')) -- From HJS


--oneLineComment :: GenParser Char st ()
oneLineComment =
  do{ try (string commentLine)
    ; skipMany (satisfy (/= '\n'))
    ; return ()
    }

--multiLineComment :: GenParser Char st ()
multiLineComment =
  do { try (string commentStart)
     ; inComment
     }

--inComment :: GenParser Char st ()
inComment
  | nestedComments = inCommentMulti
  | otherwise      = inCommentSingle

--inCommentMulti :: GenParser Char st ()
inCommentMulti
        =   do{ try (string commentEnd)              ; return () }
        <|> do{ multiLineComment                     ; inCommentMulti }
        <|> do{ skipMany1 (noneOf startEnd)          ; inCommentMulti }
        <|> do{ oneOf startEnd                       ; inCommentMulti }
        <?> "end of comment"
        where
          startEnd   = nub (commentEnd ++ commentStart)

--inCommentSingle :: GenParser Char st ()
inCommentSingle
        =   do{ try (string commentEnd)             ; return () }
        <|> do{ skipMany1 (noneOf startEnd)         ; inCommentSingle }
        <|> do{ oneOf startEnd                      ; inCommentSingle }
        <?> "end of comment"
        where
          startEnd   = nub (commentEnd ++ commentStart)

caseSensitive :: Bool
caseSensitive = True

commentStart :: [Char]
commentStart   = "/*"

commentEnd :: [Char]
commentEnd     = "*/"

commentLine :: [Char]
commentLine    = "//"

nestedComments :: Bool
nestedComments = True

identLetter = alphaNum <|> oneOf "_"
identStart  = letter <|> oneOf "_"

reservedNames :: [[Char]]
reservedNames = [ 
  "break",
  "case", "catch", "const", "continue",
  "debugger", "default", "delete", "do",
  "else", "enum",
  "false", "finally", "for", "function",
  "if", "in", "instanceof",
  "new", "null",
  "return",
  "switch",
  "this", "throw", "true", "try", "typeof",
  "var", "void",
  "while", "with"
  ]
                

--decimal :: GenParser Char st Integer
decimal         = number 10 digit

--hexadecimal :: GenParser Char st Integer
hexadecimal     = do{ oneOf "xX"; number 16 hexDigit }

--octal :: GenParser Char st Integer
octal           = do{ oneOf "oO"; number 8 octDigit  }

--number
--  :: Integer -> GenParser tok st Char -> GenParser tok st Integer
number base baseDigit
        = do{ digits <- many1 baseDigit
            ; let n = foldl (\x d -> base*x + toInteger (digitToInt d)) 0 digits
            ; seq n (return n)
            }


-- | @lexeme p@ first applies parser @p@ and than the 'whiteSpace'
-- parser, returning the value of @p@. Every lexical
-- token (lexeme) is defined using @lexeme@, this way every parse
-- starts at a point without white space. Parsers that use @lexeme@ are
-- called /lexeme/ parsers in this document.
-- 
-- The only point where the 'whiteSpace' parser should be
-- called explicitly is the start of the main parser in order to skip
-- any leading white space.
--
-- >    mainParser  = do{ whiteSpace
-- >                     ; ds <- many (lexeme digit)
-- >                     ; eof
-- >                     ; return (sum ds)
-- >                     }

--lexeme  :: forall a. ParsecT s u m a -> ParsecT s u m a,
--lexeme :: GenParser Char st b -> GenParser Char st b
--lexeme p = do{ x <- p;              whiteSpace; return x  }
lexeme p = do{ x <- p; clearNLFlag; whiteSpace; return x  }

-- ---------------------------------------------------------------------
{-
javascriptDef :: LanguageDef st
javascriptDef = javaStyle
		{ reservedNames = [ 
                     "break",
                     "case", "catch", "const", "continue",
                     "debugger", "default", "delete", "do",
                     "else", "enum",
                     "false", "finally", "for", "function",
                     "if", "in", "instanceof",
                     "new", "null",
                     "return",
                     "switch",
                     "this", "throw", "true", "try", "typeof",
                     "var", "void",
                     "while", "with"
                     ]
                -- TODO: make the following constants, so the parser defn is simpler. e,g op_COMMA = ","
                , reservedOpNames= [
                     ";"	, -- "SEMICOLON",
                     ","	, -- "COMMA",
                     "?"	, -- "HOOK",
                     ":"	, -- "COLON",
                     "||"	, -- "OR",
                     "&&"	, -- "AND",
                     "|"	, -- "BITWISE_OR",
                     "^"	, -- "BITWISE_XOR",
                     "&"	, -- "BITWISE_AND",
                     "==="	, -- "STRICT_EQ",
                     "=="	, -- "EQ",
                     "="	, -- "ASSIGN",
                     "!=="	, -- "STRICT_NE",
                     "!="	, -- "NE",
                     "<<"	, -- "LSH",
                     "<="	, -- "LE",
                     "<"	, -- "LT",
                     ">>>"	, -- "URSH",
                     ">>"	, -- "RSH",
                     ">="	, -- "GE",
                     ">"	, -- "GT",
                     "++"	, -- "INCREMENT",
                     "--"	, -- "DECREMENT",
                     "+"	, -- "PLUS",
                     "-"	, -- "MINUS",
                     "*"	, -- "MUL",
                     "/"	, -- "DIV",
                     "%"	, -- "MOD",
                     "!"	, -- "NOT",
                     "~"	, -- "BITWISE_NOT",
                     "."	, -- "DOT",
                     "["	, -- "LEFT_BRACKET",
                     "]"	, -- "RIGHT_BRACKET",
                     "{"	, -- "LEFT_CURLY",
                     "}"	, -- "RIGHT_CURLY",
                     "("	, -- "LEFT_PAREN",
                     ")"	, -- "RIGHT_PAREN",
                     "@*/"	  -- "CONDCOMMENT_END"
                ]
                , opLetter = oneOf "!%&()*+,-./:;<=>?[]^{|}~"
                , opStart = opLetter javascriptDef 
                , identStart = letter <|> oneOf "_"
                , identLetter = alphaNum <|> oneOf "_"
                               
                , caseSensitive  = True
		}
                
        
-}

-- EOF
