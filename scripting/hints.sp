#include <sdktools>

#define MAX_ANNOTATION_COUNT 50
#define MAX_ANNOTATION_LENGTH 256
#define ANNOTATION_REFRESH_RATE 0.1
#define ANNOTATION_OFFSET 8750

char
	g_sAnnotationText[MAX_ANNOTATION_COUNT][MAX_ANNOTATION_LENGTH];
float
	g_flAnnotationPosition[MAX_ANNOTATION_COUNT][3];
bool
	g_bAnnotationCanBeSeenByClient[MAX_ANNOTATION_COUNT][MAXPLAYERS+1],
	g_bAnnotationEnabled[MAX_ANNOTATION_COUNT],
	g_bHasAnnotation[MAXPLAYERS+1];
	
float
	g_flPos[3];
	
int
	g_iMinimumDistanceApart,
	g_iViewDistance;
	
Handle
	g_hCVarMinDist,
	g_hCVarViewDist;
	
	
public Plugin myinfo = 
{
	name 		= 	"Titan 2 - Hints",
	author 		= 	"Originally by Geit, Updated by myst",
	version 	= 	"2.0"
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_hint", Command_Annotate);
	
	g_hCVarMinDist = CreateConVar("sm_annotate_min_dist", "64", "Sets the minimum distance that an annotation must be from another annotation", _, true, 16.0, true, 128.0);
	g_hCVarViewDist = CreateConVar("sm_annotate_view_dist", "1024", "Sets the maximum distance at which annotations will be sent to players", _, true, 50.0);
	
	g_iMinimumDistanceApart = RoundFloat(Pow(GetConVarFloat(g_hCVarMinDist), 2.0));
	g_iViewDistance = RoundFloat(Pow(GetConVarFloat(g_hCVarViewDist), 2.0));
	
	HookConVarChange(g_hCVarMinDist, CB_MinDistChanged);
	HookConVarChange(g_hCVarViewDist, CB_ViewDistChanged);
}

public OnMapStart()
{
	CreateTimer(ANNOTATION_REFRESH_RATE, Timer_RefreshAnnotations, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	for (int i = 0; i < MAX_ANNOTATION_COUNT; i++)
	{
		if (g_bAnnotationEnabled[i]) 
			Timer_ExpireAnnotation(INVALID_HANDLE, i);
	}
}

public OnPluginEnd()
{
	for (int i = 0; i < MAX_ANNOTATION_COUNT; i++)
	{
		if (g_bAnnotationEnabled[i]) 
			Timer_ExpireAnnotation(INVALID_HANDLE, i);
	}
}

public void CB_MinDistChanged(Handle hCvar, const char[] sOldVal, const char[] sNewVal) 
{
	g_iMinimumDistanceApart = RoundFloat(Pow(StringToFloat(sNewVal), 2.0));
}

public void CB_ViewDistChanged(Handle hCvar, const char[] sOldVal, const char[] sNewVal) 
{
	g_iViewDistance = RoundFloat(Pow(StringToFloat(sNewVal), 2.0));
}

public Action Command_Annotate(int iClient, int iArgs)
{
	if (GetCmdArgs() != 1)
	{
		PrintToChat(iClient, "[SM] Usage: sm_hint <message>");
		return Plugin_Handled;
	}
	
	if (g_bHasAnnotation[iClient])
	{
		PrintToChat(iClient, "[SM] You already have an active hint.");
		return Plugin_Handled;
	}
	
	if (!SetTeleportEndPoint(iClient))
	{
		PrintToChat(iClient, "[SM] Could not find spawn point.");
		return Plugin_Handled;
	}
	
	if (NearExistingAnnotation(g_flPos))
	{
		PrintToChat(iClient, "[SM] There is already a hint here!");
		return Plugin_Handled;
	}
	
	int iAnnotation = GetFreeAnnotationID();
	if (iAnnotation == -1)
	{
		PrintToChat(iClient, "[SM] No available hints!");
		return Plugin_Handled;
	}
	
	// char strTime[4];
	char ArgString[MAX_ANNOTATION_LENGTH];
	
	// GetCmdArg(1, strTime, sizeof(strTime));
	float flTime = 7.5;
	
	GetCmdArgString(ArgString, sizeof(ArgString));
	int iPos = FindCharInString(ArgString, ' ');
	
	strcopy(g_sAnnotationText[iAnnotation], sizeof(g_sAnnotationText[]), ArgString[iPos+1]);
	g_bAnnotationEnabled[iAnnotation] = true;
	g_flAnnotationPosition[iAnnotation] = g_flPos;
	
	g_bHasAnnotation[iClient] = true;
	if (flTime > 0.0)
	{
		CreateTimer(flTime, Timer_ExpireAnnotation, iAnnotation, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(flTime, Timer_AllowAnnotation, iClient, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	PrintToChat(iClient, "[SM] Hint created.");
	return Plugin_Handled;
}

public Action Command_DeleteAnnotation(int iClient, int iArgs)
{
	if (!SetTeleportEndPoint(iClient))
	{
		PrintToChat(iClient, "[SM] Could not find end point.");
		return Plugin_Handled;
	}
	
	for (int i; i < MAX_ANNOTATION_COUNT; i++)
	{
		if (g_bAnnotationEnabled[i] && GetVectorDistance(g_flPos, g_flAnnotationPosition[i], true) < 4096)
		{
			PrintToChat(iClient, "[SM] Annotation Deleted");
			Timer_ExpireAnnotation(INVALID_HANDLE, i);
			return Plugin_Handled;
		}
	}
	
	PrintToChat(iClient, "[SM] No hints found near where you are looking!");
	return Plugin_Handled;
}

stock bool NearExistingAnnotation(float flPosition[3])
{
	for (int i = 0; i < MAX_ANNOTATION_COUNT; i++)
	{
		if (!g_bAnnotationEnabled[i])
			continue;
			
		if (GetVectorDistance(flPosition, g_flAnnotationPosition[i], true) < g_iMinimumDistanceApart)
			return true;
	}
	
	return false;
}

stock bool SetTeleportEndPoint(int iClient)
{
	float vAngles[3];
	float vOrigin[3];
	float vBuffer[3];
	float vStart[3];
	float flDistance;
	
	GetClientEyePosition(iClient, vOrigin);
	GetClientEyeAngles(iClient, vAngles);
	
    // get endpoint for teleport
	Handle hTrace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if (TR_DidHit(hTrace))
	{   	 
   	 	TR_GetEndPosition(vStart, hTrace);
		GetVectorDistance(vOrigin, vStart, false);
		flDistance = -35.0;
   	 	GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		g_flPos[0] = vStart[0] + (vBuffer[0]*flDistance);
		g_flPos[1] = vStart[1] + (vBuffer[1]*flDistance);
		g_flPos[2] = vStart[2] + (vBuffer[2]*flDistance);
	}
	
	else
	{
		CloseHandle(hTrace);
		return false;
	}
	
	CloseHandle(hTrace);
	return true;
}

public bool TraceEntityFilterPlayer(int iEntity, int contentsMask)
{
	return iEntity > GetMaxClients() || !iEntity;
}

public bool CanPlayerSee(int iClient, int iAnnotation)
{
	float flEyePos[3];
	GetClientEyePosition(iClient, flEyePos); 
	
	if (GetVectorDistance(flEyePos, g_flAnnotationPosition[iAnnotation], true) > g_iViewDistance)
		return false;
		
	TR_TraceRayFilter(flEyePos, g_flAnnotationPosition[iAnnotation], MASK_PLAYERSOLID, RayType_EndPoint, TraceEntityFilterPlayer, iClient);
	if (TR_DidHit(INVALID_HANDLE))
		return false;
		
	return true;
}

public void ShowAnnotationToPlayer(int iClient, int iAnnotation)
{
	Handle hEvent = CreateEvent("show_annotation");
	if (hEvent == INVALID_HANDLE)
		return;
		
	SetEventFloat(hEvent, "worldPosX", g_flAnnotationPosition[iAnnotation][0]);
	SetEventFloat(hEvent, "worldPosY", g_flAnnotationPosition[iAnnotation][1]);
	SetEventFloat(hEvent, "worldPosZ", g_flAnnotationPosition[iAnnotation][2]);
	SetEventFloat(hEvent, "lifetime", 99999.0);
	SetEventInt(hEvent, "id", iAnnotation*MAXPLAYERS + iClient + ANNOTATION_OFFSET);
	SetEventString(hEvent, "text", g_sAnnotationText[iAnnotation]);
	SetEventString(hEvent, "play_sound", "vo/null.wav");
	SetEventInt(hEvent, "visibilityBitfield", (1 << iClient));
	FireEvent(hEvent);
}

public int GetFreeAnnotationID()
{
	for (int i = 0; i < MAX_ANNOTATION_COUNT; i++)
	{
		if (g_bAnnotationEnabled[i])
			continue;
			
		return i;
	}
	
	return -1;
}

public void HideAnnotationFromPlayer(int iClient, int iAnnotation)
{
	Handle hEvent = CreateEvent("hide_annotation");
	if (hEvent == INVALID_HANDLE)
		return;
	
	SetEventInt(hEvent, "id", iAnnotation*MAXPLAYERS + iClient + ANNOTATION_OFFSET);
	FireEvent(hEvent);
}

public Action Timer_RefreshAnnotations(Handle hTimer, int iEntity)
{
	for (int i = 0; i < MAX_ANNOTATION_COUNT; i++)
	{
		if (!g_bAnnotationEnabled[i])
			continue;
			
		for (int iClient = 1; iClient < MaxClients; iClient++)
		{
			if (IsClientInGame(iClient) && !IsFakeClient(iClient))
			{		
				bool canClientSeeAnnotation = CanPlayerSee(iClient, i);
				if (!canClientSeeAnnotation && g_bAnnotationCanBeSeenByClient[i][iClient])
				{
					// the player can no longer see the annotation
					HideAnnotationFromPlayer(iClient, i);
					g_bAnnotationCanBeSeenByClient[i][iClient] = false;
				}
				
				else if (canClientSeeAnnotation && !g_bAnnotationCanBeSeenByClient[i][iClient])
				{
					ShowAnnotationToPlayer(iClient, i);
					g_bAnnotationCanBeSeenByClient[i][iClient] = true;
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_ExpireAnnotation(Handle hTimer, int iAnnotation)
{
	g_bAnnotationEnabled[iAnnotation] = false;
	for (int iClient = 1; iClient < MaxClients; iClient++)
	{
		if (g_bAnnotationCanBeSeenByClient[iAnnotation][iClient])
		{
			HideAnnotationFromPlayer(iClient, iAnnotation);
			g_bAnnotationCanBeSeenByClient[iAnnotation][iClient] = false;
		}
	}
	
	return Plugin_Handled;
}

public Action Timer_AllowAnnotation(Handle hTimer, int iClient) {
	g_bHasAnnotation[iClient] = false;
}