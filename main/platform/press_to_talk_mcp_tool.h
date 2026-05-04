#ifndef PRESS_TO_TALK_MCP_TOOL_H
#define PRESS_TO_TALK_MCP_TOOL_H

#include "mcp_server.h"
#include "settings.h"

// Reusable MCP tool class for press-to-talk mode
class PressToTalkMcpTool {
private:
    bool press_to_talk_enabled_;

public:
    PressToTalkMcpTool();

    // Initialize the tool and register it with the MCP server
    void Initialize();

    // Get the current press-to-talk mode state
    bool IsPressToTalkEnabled() const;

private:
    // MCP tool callback function
    ReturnValue HandleSetPressToTalk(const PropertyList& properties);

    // Internal method: set press-to-talk state and persist to settings
    void SetPressToTalkEnabled(bool enabled);
};

#endif // PRESS_TO_TALK_MCP_TOOL_H 