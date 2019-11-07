-module(chatdemo_gui).

-include_lib("wx/include/wx.hrl").
%% API
-export([start/0]).

start() ->
    wx:new(),
    Frame = wxFrame:new(wx:null(), 1, "ErlChat"),
    Panel =  wxPanel:new(Frame, []),

    MainSizer = wxBoxSizer:new(?wxVERTICAL),

    SizerEntry = wxStaticBoxSizer:new(?wxHORIZONTAL, Panel, [{label, "Enter command"}]),
    TextEntry = wxTextCtrl:new(Panel, 1, [{value, ""}, {style, ?wxDEFAULT}]),
    TextButton = wxButton:new(Panel, 10, [{label, "Send"}]),
    wxSizer:add(SizerEntry, TextEntry, [{flag, ?wxEXPAND}]),
    wxSizer:add(SizerEntry, TextButton, []),


    SizerDisplay = wxStaticBoxSizer:new(?wxVERTICAL, Panel,
        [{label, "Chats"}]),

    TextDisplay = wxTextCtrl:new(Panel, 3, [{value, ""},
        {style, ?wxDEFAULT bor ?wxTE_MULTILINE}]),

    wxSizer:add(SizerDisplay, TextDisplay, [{flag, ?wxEXPAND}, {proportion, 1}]),

    wxSizer:add(MainSizer, SizerEntry,  [{flag, ?wxEXPAND}]),
    wxSizer:addSpacer(MainSizer, 10),
    wxSizer:add(MainSizer, SizerDisplay, [{flag, ?wxEXPAND}]),
    wxPanel:setSizer(Panel, MainSizer),

    wxFrame:show(Frame),

    timer:sleep(30000),
    wx:destroy(),
    ok.







