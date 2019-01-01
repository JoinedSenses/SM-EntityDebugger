/*
	To Do:
	- Continue testing (especially var str/ent input)
	- Ability to retrieve more info from triggers?
	- Maybe more info about cp's/tca's?
	- Solicit feedback from others who would use this (mappers?)
	- Maybe add support for things from other games - requires feedback
	- Sleep
 */

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "color_literals.inc"

#define PLUGIN_VERSION "0.0.2"
#define PLUGIN_DESCRIPTION "Tool for debugging entities"
#define EF_NODRAW 32
#define MAX_EDICT_COUNT 2048

enum DataType {
	TYPEINT,
	TYPEFLOAT,
	TYPESTRING
}

ArrayList g_aVisibleEntities;

StringMap g_smCapturePoint;
StringMap g_smCapturePointName;

//int g_iAreaCount;
//int g_iCPCount;
int g_iBeamSprite;
int g_iHaloSprite;
int g_iOffset_m_fEffects;

bool g_bDebug[MAXPLAYERS+1];

char g_sFilePath[128];
char g_sEntityList[][] = {
	"func_brush",
	"func_button",
	"func_door",
	"func_clip_vphysics",
	"func_nogrenades",
	"func_nobuild",
	"prop_dynamic",
	"trigger_capture_area",
	"trigger_catapult",
	"trigger_teleport",
	"trigger_push"
};

public Plugin myinfo = {
	name =  "Entity Debugger",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
}

public void OnPluginStart() {
	CreateConVar("sm_entitydebugger_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);
	RegAdminCmd("sm_entdebug", cmdCapDebugger, ADMFLAG_GENERIC, "Toggle debug mode");
	RegAdminCmd("sm_gethammerid", cmdGetHammerId, ADMFLAG_GENERIC, "Point, shoot, ???, profit");

	RegAdminCmd("sm_hasprop", cmdHasProp, ADMFLAG_GENERIC, "sm_hasprop <entity> <proptype[send/data]> <propname>");
	RegAdminCmd("sm_getentprop", cmdGetProp, ADMFLAG_ROOT, "sm_getentprop <returntype[e,i,f,s,v]> <entity> <proptype[send/data]> <propname>");
	RegAdminCmd("sm_setentprop", cmdSetProp, ADMFLAG_ROOT, "sm_setentprop <entity> <proptype[send/data]> <propname> <value(int,float,string,vector)>"); 
	// Considering consolidating into above command to allow specifying type, instead of attempting to "intelligently" determine value type - see: CheckType()
	RegAdminCmd("sm_setentpropent", cmdSetPropEnt, ADMFLAG_ROOT, "sm_setentpropent <entity1> <proptype[send/data]> <propname> <entity2>");

	RegAdminCmd("sm_setvariantstring", cmdSetVarStr, ADMFLAG_ROOT, "SetVariantString - Sets variant string and execs AcceptEntityInput");
	RegAdminCmd("sm_acceptentityinput", cmdEntInput, ADMFLAG_ROOT, "AcceptEntityInput - Execs AcceptEntityInput");

	RegAdminCmd("sm_dumpentities", cmdDump, ADMFLAG_ROOT, "Logs entities to addons/sourcemod/logs/entities/map_name_entities.txt");

	HookEvent("controlpoint_starttouch", eventTouchCP);
	HookEvent("teamplay_round_start", eventRoundStart);

	g_aVisibleEntities = new ArrayList();
	g_smCapturePoint = new StringMap();
	g_smCapturePointName = new StringMap();

	g_iOffset_m_fEffects = FindSendPropInfo("CBaseEntity", "m_fEffects");

	BuildPath(Path_SM, g_sFilePath, sizeof(g_sFilePath), "logs/entities");
	if (!DirExists(g_sFilePath)) {
		CreateDirectory(g_sFilePath, 511);
		if (!DirExists(g_sFilePath)) {
			SetFailState("Failed to create directory at %s - Please manually create that path and reload this plugin.", g_sFilePath);
		}
	}
}

public void OnMapStart() {
	g_iBeamSprite = PrecacheModel("sprites/laser.vmt", true);
	g_iHaloSprite = PrecacheModel("sprites/halo01.vmt", true);

	Setup();
}

public void eventRoundStart(Handle event, const char[] name, bool dontBroadcast) {
	Setup();
}

void Setup() {
	g_smCapturePoint.Clear();
	g_smCapturePointName.Clear();

	char name[32];
	char areaidx[3];
	int entity;
	// Hooks control points - Useful for TF2, unsure of other games
	while ((entity = FindEntityByClassname(entity, "team_control_point")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iszPrintName", name, sizeof(name));
		g_smCapturePoint.SetValue(name, entity);

		Format(areaidx, sizeof(areaidx), "%i", GetEntProp(entity, Prop_Data, "m_iPointIndex"));
		g_smCapturePointName.SetString(areaidx, name);
		//g_iCPCount++;
	}
	// Hooks triggers for control points - Useful for TF2, unsure of other games
	while ((entity = FindEntityByClassname(entity, "trigger_capture_area")) != INVALID_ENT_REFERENCE) {
		SDKHook(entity, SDKHook_StartTouchPost, hookTCAStartTouchPost);
		//g_iAreaCount++;
	}
	// Hooks teleports.
	while ((entity = FindEntityByClassname(entity, "trigger_teleport")) != INVALID_ENT_REFERENCE) {
		SDKHook(entity, SDKHook_StartTouch, hookTeleStartTouch);
	}
}

public void OnPluginEnd() {
	int len;
	if ((len = g_aVisibleEntities.Length)) {
		for (int i = 0; i < len; i++) {
			// If there are still any visible triggers, hide them.
			hideTrigger(g_aVisibleEntities.Get(i));
		}
	}
}

public Action cmdCapDebugger(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	g_bDebug[client] = !g_bDebug[client];
	PrintToEnabled(false, "Map debugging\x03 %s\x01 for\x03 %N", g_bDebug[client] ? "enabled" : "disabled", client);
	return Plugin_Handled;
}

public Action cmdGetHammerId(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}
	// Trace ray, enumerates entities, prints some info, makes triggers visible
	LazerBeam(client);
	
	return Plugin_Handled;
}

public Action cmdHasProp(int client, int args) {
	if (args < 3) {
		ReplyToCommand(client, "Usage: sm_hasprop <entity> <proptype[send/data]> <propname>");
		return Plugin_Handled;
	}

	char buffer[32];
	GetCmdArg(1, buffer, sizeof(buffer));

	int entity = StringToInt(buffer);

	if (!IsValidEntity(entity)) {
		ReplyToCommand(client, "Invalid entity %i", entity);
		return Plugin_Handled;
	}
	
	GetCmdArg(2, buffer, sizeof(buffer));
	// Maybe consider using just d/s instead of full word
	PropType proptype;
	if (StrEqual(buffer, "data", false)) {
		proptype = Prop_Data;
	}
	else if (StrEqual(buffer, "send", false)) {
		proptype = Prop_Send;
	}
	else {
		ReplyToCommand(client, "Unknown prop type %s", buffer);
		return Plugin_Handled;
	}

	GetCmdArg(3, buffer, sizeof(buffer));

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	ReplyToCommand(client, "%i %s prop_%s %s | %s", entity, classname, proptype ? "data" : "send", buffer, HasEntProp(entity, proptype, buffer) ? "Yes" : "No");
	return Plugin_Handled;
}

public Action cmdGetProp(int client, int args) {
	if (args < 3) {
		ReplyToCommand(client, "Usage: sm_getentprop <type[e,i,f,s,v]> <entity> <proptype[send/data]> <propName>");
		return Plugin_Handled;
	}

	char type[3];
	GetCmdArg(1, type, sizeof(type));

	if (strlen(type) > 1) {
		// entity, int, float, string, vector
		ReplyToCommand(client, "Invalid parameter. Parameters: e, i, f, s, v");
		return Plugin_Handled;
	}

	char sEnt[5];
	GetCmdArg(2, sEnt, sizeof(sEnt));

	int entity = StringToInt(sEnt);

	if (!IsValidEntity(entity)) {
		ReplyToCommand(client, "Invalid entity %i", entity);
		return Plugin_Handled;
	}

	char prop[5];
	GetCmdArg(3, prop, sizeof(prop));

	PropType proptype;
	if (StrEqual(prop, "data", false)) {
		proptype = Prop_Data;
	}
	else if (StrEqual(prop, "send", false)) {
		proptype = Prop_Send;
	}
	else {
		ReplyToCommand(client, "Unknown prop type %s", prop);
		return Plugin_Handled;
	}

	char propname[64];
	GetCmdArg(4, propname, sizeof(propname));

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (!HasEntProp(entity, proptype, propname)) {
		ReplyToCommand(client, "%i %s | No prop type %s for prop_%s", entity, classname, propname, proptype ? "data" : "send");
		return Plugin_Handled;
	}

	/* I wish I knew of a way to retrieve ent prop data type instead of requiring a param. Errors with no info if incorrect params are used.
	   Deathreus suggested using "inline SendPropType SendProp::GetType() const", which I think would mean an extension would need to be created for this.
	   As far as I know, SourceMod doesn't provide this functionality. */
	switch (type[0]) {
		case 'e', 'E': {
			int value = GetEntPropEnt(entity, proptype, propname);
			ReplyToCommand(client, "%i %s | prop_%s %s Value: %i", entity, classname, prop, propname, value);
		}
		case 'i', 'I': {
			int value = GetEntProp(entity, proptype, propname);
			ReplyToCommand(client, "%i %s | prop_%s %s Value: %i", entity, classname, prop, propname, value);
		}
		case 'f', 'F': {
			float value = GetEntPropFloat(entity, proptype, propname);
			ReplyToCommand(client, "%i %s | prop_%s %s Value: %f", entity, classname, prop, propname, value);
		}
		case 's', 'S': {
			char value[64];
			GetEntPropString(entity, proptype, propname, value, sizeof(value));
			ReplyToCommand(client, "%i %s | prop_%s %s Value: %s", entity, classname, prop, propname, value);
		}
		case 'v', 'V': {
			float value[3];
			GetEntPropVector(entity, proptype, propname, value);
			ReplyToCommand(client, "%i %s | prop_%s %s Value: {%0.2f, %0.2f, %0.2f}", entity, classname, prop, propname, value[0], value[1], value[2]);
		}
		default: {
			ReplyToCommand(client, "Usage: sm_getentprop <type[e,i,f,s,v]> <entity> <proptype[send/data]> <propName>");
		}
	}
	return Plugin_Handled;
}

public Action cmdSetProp(int client, int args) {
	// Maybe consider adding param for return type instead of attempting to determine value data type - See: CheckType()
	if (args < 4) {
		ReplyToCommand(client, "Usage: sm_setentprop <entity> <proptype[send/data]> <propName> <Value[int,float,string,vector]>");
		return Plugin_Handled;
	}

	char buffer[32];
	GetCmdArg(1, buffer, sizeof(buffer));
	int entity = StringToInt(buffer);
	
	GetCmdArg(2, buffer, sizeof(buffer));

	PropType propType;
	if (StrEqual(buffer, "data", false)) {
		propType = Prop_Data;
	}
	else if (StrEqual(buffer, "send", false)) {
		propType = Prop_Send;
	}
	else {
		ReplyToCommand(client, "Unknown prop type");
		return Plugin_Handled;
	}

	GetCmdArg(3, buffer, sizeof(buffer));

	char newValue[128];
	if (args == 6) {
		char temp1[32];
		GetCmdArg(4, temp1, sizeof(temp1));

		char temp2[32];
		GetCmdArg(5, temp2, sizeof(temp2));

		char temp3[32];
		GetCmdArg(6, temp3, sizeof(temp3));

		Format(newValue, sizeof(newValue), "%s %s %s", temp1, temp2, temp3);
	}
	else {
		GetCmdArg(4, newValue, sizeof(newValue));
	}

	SetProp(client, entity, propType, buffer, newValue);

	return Plugin_Handled;
}

public Action cmdSetPropEnt(int client, int args) {
	if (args < 4) {
		ReplyToCommand(client, "Usage: sm_setentpropent <entity1> <proptype[send/data]> <propname> <entity2>");
		return Plugin_Handled;
	}

	char buffer[32];
	GetCmdArg(1, buffer, sizeof(buffer));
	int entity1 = StringToInt(buffer);

	if (!IsValidEntity(entity1)) {
		ReplyToCommand(client, "Invalid entity %i", entity1);
		return Plugin_Handled;
	}

	char sPropType[32];
	GetCmdArg(2, sPropType, sizeof(sPropType));

	PropType proptype;
	if (StrEqual(buffer, "data", false)) {
		proptype = Prop_Data;
	}
	else if (StrEqual(buffer, "send", false)) {
		proptype = Prop_Send;
	}
	else {
		ReplyToCommand(client, "Unknown prop type");
		return Plugin_Handled;
	}

	char propname[32];
	GetCmdArg(3, propname, sizeof(propname));

	char classname1[32];
	GetEntityClassname(entity1, classname1, sizeof(classname1));

	if (!HasEntProp(entity1, proptype, buffer)) {
		ReplyToCommand(client, "%i %s | No prop type %s for prop_%s", entity1, classname1, propname, proptype ? "data" : "send");
		return Plugin_Handled;
	}

	GetCmdArg(4, buffer, sizeof(buffer));
	int entity2 = StringToInt(buffer);

	if (!IsValidEntity(entity2)) {
		ReplyToCommand(client, "Invalid entity %i", entity2);
		return Plugin_Handled;
	}

	char classname2[32];
	GetEntityClassname(entity1, classname1, sizeof(classname2));

	SetEntPropEnt(entity1, proptype, propname, entity2);
	ReplyToCommand(client, "%i %s | %s set to %i %s", entity1, classname1, propname, entity2, classname2);

	return Plugin_Handled;
}

void SetProp(int client, int entity, PropType proptype, const char[] propname, const char[] value) {
	if (!IsValidEntity(entity)) {
		ReplyToCommand(client, "Invalid entity %i", entity);
		return;
	}

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (!HasEntProp(entity, proptype, propname)) {
		ReplyToCommand(client, "%i %s | No prop type %s for prop_%s", entity, classname, propname, proptype ? "data" : "send");
		return;
	}

	char buffer[3][32];
	float vFloat[3];

	if (StrContains(value, " ") != -1) {
		ExplodeString(value, " ", buffer, sizeof(buffer), sizeof(buffer[]));
		vFloat[0] = StringToFloat(buffer[0]);
		vFloat[1] = StringToFloat(buffer[1]);
		vFloat[2] = StringToFloat(buffer[2]);
		SetEntPropVector(entity, proptype, propname, vFloat);
		ReplyToCommand(client, "%i %s | %s set to %0.2f %0.2f %0.2f", entity, classname, propname, vFloat[0], vFloat[1], vFloat[2]);
		return;
	}

	DataType datatype = CheckType(value, strlen(value));
	switch(datatype) {
		case TYPEINT: {
			int iValue = StringToInt(value);
			SetEntProp(entity, proptype, propname, iValue);
			ReplyToCommand(client, "%i %s | %s set to %i", entity, classname, propname, iValue);
		}
		case TYPEFLOAT: {
			float fValue = StringToFloat(value);
			SetEntPropFloat(entity, proptype, propname, fValue);
			ReplyToCommand(client, "%i %s | %s set to %f", entity, classname, propname, fValue);
		}
		case TYPESTRING: {
			char sValue[64];
			Format(sValue, sizeof(sValue), value);
			SetEntPropString(entity, proptype, propname, sValue);
			ReplyToCommand(client, "%i %s | %s set to %s", entity, classname, propname, sValue);
		}
	}
}

DataType CheckType(const char[] input, int size) {
	int numbers = 0;
	int dot = 0;
	for (int i = (input[0] == '-') ? 1 : 0; i < size; i++) {
		if (IsCharNumeric(input[i])) {
			numbers++;
		}
		else if (input[i] == '.') {
			dot++;
		}
		else {
			return TYPESTRING;
		}
	}
	if (numbers > 0 && dot <= 1) {
		return (dot == 1) ? TYPEFLOAT : TYPEINT;
	}
	return TYPESTRING;
}

public Action cmdSetVarStr(int client, int args) {
	// i've never personally used setvarstring/acceptentityinput outside of some copy/paste stocks. Not exactly certain of usecase for this.
	if (args < 3) {
		ReplyToCommand(client, "Usage: sm_setvariantstring <\"variantStr\"> <entity> <\"inputstr\"> | <activator> <caller> <outputid>");
		return Plugin_Handled;		
	}

	char varstr[63];
	GetCmdArg(1, varstr, sizeof(varstr));

	char sEnt[8];
	GetCmdArg(2, sEnt, sizeof(sEnt));
	int entity = StringToInt(sEnt);

	if (!IsValidEntity(entity)) {
		ReplyToCommand(client, "Invalid entity %i", entity);
		return Plugin_Handled;
	}

	char inputarg[32];
	GetCmdArg(3, inputarg, sizeof(inputarg));

	char buffer[4][32] = {"-1", "-1", "-1", "0"};

	for (int i = 2; i <= args && i <= 6; i++) {
		GetCmdArg(i, buffer[i-2], sizeof(buffer[]));
	}

	AcceptEntityInput(entity, buffer[0], StringToInt(buffer[1]), StringToInt(buffer[2]), StringToInt(buffer[3]));

	char arg[64];
	GetCmdArgString(arg, sizeof(arg));
	
	SetVariantString(varstr);
	ReplyToCommand(client, "Executed %s %s %s %s on %i", buffer[0], buffer[1], buffer[2], buffer[3], entity);
	return Plugin_Handled;
}

public Action cmdEntInput(int client, int args) {
	// i've never personally used setvarstring/acceptentityinput outside of some copy/paste stocks. Not exactly certain of usecase for this.
	if (args < 2) {
		ReplyToCommand(client, "Usage: sm_setvariantstring <entity> <\"inputstr\"> | <activator> <caller> <outputid>");
		return Plugin_Handled;		
	}

	char sEnt[8];
	GetCmdArg(1, sEnt, sizeof(sEnt));
	int entity = StringToInt(sEnt);

	if (!IsValidEntity(entity)) {
		ReplyToCommand(client, "Invalid entity %i", entity);
		return Plugin_Handled;
	}

	char inputarg[32];
	GetCmdArg(2, inputarg, sizeof(inputarg));

	char buffer[4][32] = {"-1", "-1", "-1", "0"};

	for (int i = 2; i <= args && i <= 6; i++) {
		GetCmdArg(i, buffer[i-2], sizeof(buffer[]));
	}

	AcceptEntityInput(entity, buffer[0], StringToInt(buffer[1]), StringToInt(buffer[2]), StringToInt(buffer[3]));

	char arg[64];
	GetCmdArgString(arg, sizeof(arg));
	
	ReplyToCommand(client, "Executed %s %s %s %s on %i", buffer[0], buffer[1], buffer[2], buffer[3], entity);
	return Plugin_Handled;
}

public Action cmdDump(int client, int args) {
	char mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));

	BuildPath(Path_SM, g_sFilePath, sizeof(g_sFilePath), "/logs/entities/%s_entities.txt", mapName);

	char ent[64];
	char classname[PLATFORM_MAX_PATH];
	
	File file = OpenFile(g_sFilePath, "w");
	
	int count;
	for (int i = 0; i <= MAX_EDICT_COUNT; i++) {
		if(IsValidEdict(i)) {
			GetEdictClassname(i, classname, sizeof(classname));

			Format(ent, sizeof(ent), "%04i|%s", i, classname);

			file.WriteLine(ent);
			count++;
		}
	}

	file.Close();
	PrintToChat(client, "Wrote %i entities to log", count);
	return Plugin_Handled;
}



void LazerBeam(int client) {
	// Probably my favorite thing about this plugin. It's been pretty useful. Maybe I should print more information? Need feedback.
	g_bDebug[client] = true; 

	float origin[3];
	float angles[3];
	
	GetClientEyePosition(client, origin);
	GetClientEyeAngles(client, angles);
	
	Handle trace = TR_TraceRayFilterEx(origin, angles, MASK_SOLID_BRUSHONLY, RayType_Infinite, TraceEntityFilterNoClients);

	int entity;
	
	if (TR_DidHit(trace)) {
		float end[3];
		TR_GetEndPosition(end, trace);

		entity = TR_GetEntityIndex(trace);

		TR_EnumerateEntities(origin, end, PARTITION_TRIGGER_EDICTS, RayType_EndPoint, TREnumTrigger);
		TR_EnumerateEntities(origin, end, PARTITION_SOLID_EDICTS|PARTITION_STATIC_PROPS, RayType_EndPoint, TREnumSolid);

		origin[2] -= 15;
		TE_SetupBeamPoints(origin, end, g_iBeamSprite, g_iHaloSprite, 0, 66, 10.0, 2.0, 2.0, 1, 1.0, {255, 255, 255, 255}, 0);
		TE_SendToAll(0.1);

		PrintToEnabled(_, "\x05Hit|\x01 %0.2f\x05,\x01 %0.2f\x05,\x01 %0.2f", end[0], end[1], end[2]);
	}

	delete trace;

	if (!entity) {
		return;
	}
}

bool TraceEntityFilterNoClients(int entity, int contentsMask) {
	// Ignore clients
	return (entity > MaxClients);
}

bool TREnumTrigger(int entity) {
	// Only displays some information about triggers from g_sEntityList. edit as need.
	if (entity <= MaxClients) {
		return true;
	}

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	int model = HasEntProp(entity, Prop_Data, "m_nModelIndex") ? GetEntProp(entity, Prop_Data, "m_nModelIndex") : -1;

	for (int i = 0; i < sizeof(g_sEntityList); i++) {
		if (StrEqual(classname, g_sEntityList[i])) {
			PrintToEnabled(_, "\x05Ent:\x01 %i \x05ID:\x01 %i \x05Class:\x01 %s \x05Model:\x01 %i", entity, GetHammerId(entity), classname, model);
			
			showTrigger(entity);
			return true;
		}
	}

	return true;
}

Action timerHideTrigger(Handle timer, int entity) {
	hideTrigger(entity);
}

bool TREnumSolid(int entity) {
	// Pretty much anything that isnt a trigger/func/brush
	if (entity <= MaxClients) {
		return true;
	}

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	int model = HasEntProp(entity, Prop_Data, "m_nModelIndex") ? GetEntProp(entity, Prop_Data, "m_nModelIndex") : -1;

	PrintToEnabled(_, "\x05ID:\x01 %i \x05Class:\x01 %s \x05Model:\x01 %i", GetHammerId(entity), classname, model);

	return true;
}

public Action hookTeleStartTouch(int entity, int other) {
	// Hook for teleports. Will trigger if touched by client or an entity that has m_hOwnerEntity prop, such as rockets.
	int client;
	if (!(client = IsValidClient(other)) || !g_bDebug[client]) {
		return Plugin_Continue;
	}

	int hammerid = GetHammerId(entity);
	char destination[32];
	GetEntPropString(entity, Prop_Data, "m_target", destination, sizeof(destination));

	char name[32];
	GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));

	int targetentity;
	int targethammerid;
	char buffer[32];
	while ((targetentity = FindEntityByClassname(targetentity, "info_teleport_destination")) != -1) {
		GetEntPropString(targetentity, Prop_Data, "m_iName", buffer, sizeof(buffer));    
		if (StrEqual(buffer, destination)) {
			targethammerid = GetHammerId(targetentity);
			break;
		}
	}

	PrintToEnabled(_, "\x05Tele Trigger:\x01 %i %s \x05Dest:\x01 %i %s", hammerid, name, targethammerid, destination);

	return Plugin_Continue;
}

public Action hookTCAStartTouchPost(int entity, int other) {
	// Hook for trigger_capture_area. Will trigger if touched by client or an entity that has m_hOwnerEntity prop, such as rockets.
	int client;
	if (!(client = IsValidClient(other)) || !g_bDebug[client]) {
		return Plugin_Continue;
	}

	int hammerid = GetHammerId(entity);

	char name[32];
	GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));

	char target[32];
	GetEntPropString(entity, Prop_Data, "m_iszCapPointName", target, sizeof(target));

	int targetentity;
	int targethammerid;
	char targetname[32];
	char targetprintname[32];
	bool found;
	while ((targetentity = FindEntityByClassname(targetentity, "team_control_point")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(targetentity, Prop_Data, "m_iName", targetname, sizeof(targetname));

		if (StrEqual(targetname, target)) {
			targethammerid = GetHammerId(targetentity);
			GetEntPropString(targetentity, Prop_Data, "m_iszPrintName", targetprintname, sizeof(targetprintname));
			found = true;
			break;
		}
	}

	if (found) {
		PrintToEnabled(_, "\x05%s\x01|\x05Trigger:\t\x01 %i %s \x05\n%s\x01|\x05CP:\t\t\x01 %i %s", target, hammerid, name, targetname, targethammerid, targetprintname);
	}
	else {
		PrintToEnabled(_, "\x05Trigger:\x01 %i %s", hammerid, name);
	}
	

	return Plugin_Continue;
}

public Action eventTouchCP(Event event, const char[] name, bool dontBroadcast) {
	// Hook for control point events. Will trigger if touched by client (as long as control point has been correctly made by mapper)
	int client = event.GetInt("player");
	if (!g_bDebug[client]) {
		return Plugin_Continue;
	}

	int area = event.GetInt("area");
	char areaidx[3];
	Format(areaidx, sizeof(areaidx), "%i", area);

	char cpname[32];
	g_smCapturePointName.GetString(areaidx, cpname, sizeof(cpname));

	int entity;
	g_smCapturePoint.GetValue(cpname, entity);

	int hammerid = GetHammerId(entity);
	PrintToEnabled(_, "\x05CP\x01 | \x05idx:\x01%i \x05name:\x01%s \x05hammerid:\x01%i", area, cpname, hammerid);
	return Plugin_Continue;
}

int GetHammerId(int entity) {
	return HasEntProp(entity, Prop_Data, "m_iHammerID") ? GetEntProp(entity, Prop_Data, "m_iHammerID") : -1;
}

int IsValidClient(int client) {
	// check for valid client...
	if (0 < client <= MaxClients && IsClientInGame(client)) {
		return client;
	}
	// ... or if it was a projectile or whatever
	int owner;
	if (client > MaxClients && HasEntProp(client, Prop_Data, "m_hOwnerEntity") && (0 < (owner = GetEntPropEnt(client, Prop_Data, "m_hOwnerEntity")) <= MaxClients) && IsClientInGame(owner)) {
		return owner;
	}
	return 0;
}

bool IsValidAdmin(int client) {
	// edit as need. this is just to ensure messages are only sent to those who can use debug mode and while it's enabled.
	int player;
	return ((player = IsValidClient(client)) > 0 && CheckCommandAccess(player, "sm_mapdebug_override", ADMFLAG_GENERIC));
}

void PrintToEnabled(bool debugonly = true, const char[] msg, any ...) {
	char messageBuffer[192];
	VFormat(messageBuffer, sizeof(messageBuffer), msg, 3);

	for (int i = 1; i <= MaxClients; i++) {
		if ((!debugonly && IsValidAdmin(i) || g_bDebug[i])) {
			PrintColoredChatEx(i, CHAT_SOURCE_SERVER, messageBuffer);
		}
	}
}

void showTrigger(int entity) {
	// some code i used from the sm_showtriggers plugin. makes triggers visible
	int effectFlags = GetEntData(entity, g_iOffset_m_fEffects);
	int edictFlags = GetEdictFlags(entity);

	if (!(edictFlags & FL_EDICT_DONTSEND)) {
		return;
	}

	effectFlags &= ~EF_NODRAW;
	edictFlags &= ~FL_EDICT_DONTSEND;

	SetEntData(entity, g_iOffset_m_fEffects, effectFlags);
	ChangeEdictState(entity, g_iOffset_m_fEffects);
	SetEdictFlags(entity, edictFlags);

	SDKHook(entity, SDKHook_SetTransmit, hookSetTransmit);

	CreateTimer(5.0, timerHideTrigger, entity);
	g_aVisibleEntities.Push(entity);
}

void hideTrigger(int entity) {
	if (!IsValidEntity(entity)) {
		return;
	}

	int effectFlags = GetEntData(entity, g_iOffset_m_fEffects);
	int edictFlags = GetEdictFlags(entity);

	effectFlags |= EF_NODRAW;
	edictFlags |= FL_EDICT_DONTSEND;

	SetEntData(entity, g_iOffset_m_fEffects, effectFlags);
	ChangeEdictState(entity, g_iOffset_m_fEffects);
	SetEdictFlags(entity, edictFlags);

	SDKUnhook(entity, SDKHook_SetTransmit, hookSetTransmit);
	g_aVisibleEntities.Erase(0);
}

public Action hookSetTransmit(int entity, int other) {
	// hook transmit so that we can make the triggers visible, but only transmit them to those who have debug enabled
	if (other <= MaxClients && g_bDebug[other]) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}