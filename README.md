# SM-EntityDebugger
Tool for debugging maps/entities

Requires (SM 1.10) or (SDKTools extension version + SM 1.9) found here:  
https://github.com/JoinedSenses/Sourcemod-SDKTools

## ConVars
* ```sm_entitydebugger_triggerfilter```  
Toggle use of the trigger filter: see g_sEntityFilterList. When enabled, only those in the list will be active

## Commands
* ```sm_entdebug```  
Toggle debug mode  
  
* ```sm_gethammerid```  
Shoots lazer beam, provides info about entities it hits (Triggers are whitelisted, see: g_sEntityList) , toggles visibility of triggers and enables debug mode  
  
* ```sm_hasprop <entity> <proptype[data/send]> <"propname">```  
Checks if ent has prop  
  
* ```sm_getentprop <returntype[e,i,f,s,v]> <entity> <proptype[data/send]> <propname>```  
Retrieve prop value - Logs to error if incorrect returntype is specified for propname  
  
* ```sm_setentprop <entity> <proptype[data/send]> <propname> <Value[int,float,string,vector]>```  
Sets prop value  

* ```sm_setentpropent <entity1> <proptype[data/send]> <propname> <entity2>```  
Sets prop ent value  
  
* ```sm_setvariantstring <"variantStr"> <entity> <"inputstr"> | OPTIONAL: <activator> <caller> <outputid>```  
Untested - Set variant string and run AcceptEntityInput(entity, "inputstr", activator, caller, outputit)  
  
* ```sm_acceptentityinput <entity> <"inputstr"> | OPTIONAL: <activator> <caller> <outputid>```  
Same as previous command, except it doesn't set variant string  

* ```sm_triggerfiler```  
Toggles the triggerfilter cvar  
  
* ```sm_dumpentities```  
Dumps entities to /addons/sourcemod/logs/entities/map_name_entities.log  
  
* ```sm_findentities <"classname">```  
Finds entities that match classname and prints to info to console  
