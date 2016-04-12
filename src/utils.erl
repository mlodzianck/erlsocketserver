-module(utils).
-author("maciejtokarski").

-export([generate_random_str/1]).


get_random_string(Length, AllowedChars) ->
  [lists:nth(random:uniform(length(AllowedChars)),AllowedChars) ||  _ <- lists:seq(0,Length-1) ].


generate_random_str(Len) ->
  get_random_string(Len,"QWERTYUIOPASDFGHJKLZXCVBNMqwertyuiopasdfghjklzxcvbnm1234567890").