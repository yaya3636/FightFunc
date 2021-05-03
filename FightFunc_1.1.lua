AI_FILE = "ModSpellPriority.lua"

local minPercentLifeBeforeAttack = 80

local minMonster = 1
local maxMonster = 4

local MONSTERS_CONF = {
    {
        idMonster = 78,
        min = 0,
        max = 8
    } 
}

local PATH = {
    { map = "153880322", path = "left" },
    { map = "153879810", path = "left" },
    { map = "153879298", path = "bottom" },
    { map = "153879297", path = "right" },
    { map = "153879809", path = "right" },
    { map = "153880321", path = "top" }
}

local MAP_DATA_MONSTERS = {}
local SORTED_MONSTERS = {}
local MONSTERS_TO_ATTACK = {}

function move()
    Fight()

    return PATH
end

function stopped()
    PacketSubManager("fight")    
end

-- Gestion des packet
    function PacketSubManager(pType, register)
        local allSub = false

        local packetToSub = {
            ["Fight"] = {
                ["MapComplementaryInformationsDataMessage"] = CB_MapComplementaryInfoDataMessage,
                ["GameRolePlayShowActorMessage"] = CB_ShowActorMessage,    
                ["GameContextRemoveElementMessage"] = CB_ContextRemoveElementMessage,              
                ["GameMapMovementMessage"] = CB_MapMovementMessage,
                ["GameFightStartingMessage"] = CB_FightStartingMessage               
            }
        }

        -- Gestion params
        if type(pType) == "boolean" then
            register = pType
            allSub = true
        elseif pType == nil then
            allSub = true
        end

        -- Logic 
        for kType, vPacketTbl in pairs(packetToSub) do
            if allSub then
                pType = kType
            end
            if string.lower(kType) == string.lower(pType) then
                for packetName, callBack in pairs(vPacketTbl) do
                    if register then -- Abonnement au packet
                        if not developer:isMessageRegistred(packetName) then
                            Print("Abonnement au packet : "..packetName, "packet")
                            developer:registerMessage(packetName, callBack)
                        end            
                    else -- Désabonnement des packet
                        if developer:isMessageRegistred(packetName) then
                            Print("Désabonnement du packet : "..packetName, "packet")
                            developer:unRegisterMessage(packetName)
                        end            
                    end
                end
            end
        end
    end

    function PacketSender(packetName, fn)
        Print("Envoie du packet "..packetName, "packet")
        local msg = developer:createMessage(packetName)

        if fn ~= nil then
            msg = fn(msg)
        end

        developer:sendMessage(msg)
    end

-- Fight Manager

    function Fight(config)
        if config ~= nil then
            minMonster = config.minMonster
            maxMonster = config.maxMonster
            MONSTERS_CONF = config.conf
        end
        PacketSubManager("fight", true)

        if character:lifePointsP() < minPercentLifeBeforeAttack then
            Print("Régéneration des PV avant reprise des combats", "fight")
            while character:lifePoints() < character:maxLifePoints() do
                global:delay(1500)
            end
            Print("Fin de régéneration des PV reprise des combats", "fight")
        end

        -- Tri des fight possible

        for _, v in pairs(MAP_DATA_MONSTERS) do
            if MeetConditionsToAttack(v.idMonster) then
                table.insert(SORTED_MONSTERS, v)
            end
        end

        while #SORTED_MONSTERS > 0 do
            -- Séléction et suppresion du grp
            for i = #SORTED_MONSTERS, 1, -1 do
                MONSTERS_TO_ATTACK = SORTED_MONSTERS[i]
                table.remove(SORTED_MONSTERS, i)
                break
            end

            if map:currentCell() ~= MONSTERS_TO_ATTACK.cellId then
                Print("Déplacement vers la cellule du lancement de combat", "fight")
                map:moveToCell(MONSTERS_TO_ATTACK.cellId)
                developer:unRegisterMessage("GameMapMovementMessage")
                TryAttack(MONSTERS_TO_ATTACK.contextualId)
            end
        end
    end

    function TryAttack(ctxId)
        Print("Tentative attack", 'fight')

        PacketSender("GameRolePlayAttackMonsterRequestMessage", function(msg)
            msg.monsterGroupId = ctxId
            return msg
        end)

        if not developer:suspendScriptUntil("GameFightStartingMessage", 2500, false) then
            Print("Le lancement du combat a échoué", "TryAttack", "error")
        end
    end

    function MeetConditionsToAttack(tblIdMonsters)
        local verified = {}

        if #tblIdMonsters < minMonster or #tblIdMonsters > maxMonster then
            return false
        end

        for _, conf in pairs(MONSTERS_CONF) do
            local count = CountIdenticValue(tblIdMonsters, conf.idMonster)
            --Print("Count = "..count.." id = "..conf.idMonster.." min = "..conf.min.." max = "..conf.max)
            if (count >= conf.min) and (count <= conf.max) then
                --Print("True")
                table.insert(verified, true)
            else
                --Print("False")
                table.insert(verified, false)
            end
        end

        for _, v in pairs(verified) do
            if v == false then
                return false
            end
        end

        return true
    
    end


-- CallBack FightPacket

    function CB_MapComplementaryInfoDataMessage(packet)
        --Print("MapComplementary")
        MAP_DATA_MONSTERS = Get_SortedGroupMonster(packet.actors)
    end

    function CB_ShowActorMessage(packet)
       -- Print("ShowActor")
        if developer:typeOf(packet.informations) == "GameRolePlayGroupMonsterInformations" then
            local updated = false
            local sortedGroup = Get_SortedGroupMonster({packet.informations})

            for _, v in pairs(SORTED_MONSTERS) do
                if v.contextualId == sortedGroup[1].contextualId then
                    updated = true
                    --Print("Update groupMonster")
                    v = sortedGroup[1]
                    break
                end
            end

            if not updated then
                if MONSTERS_TO_ATTACK.contextualId ~= sortedGroup[1].contextualId and MeetConditionsToAttack(sortedGroup[1].idMonster) then
                    --Print("Ajouter a SORTED")
                    table.insert(MAP_DATA_MONSTERS, sortedGroup[1])
                end
            end
        end
    end
    
    function CB_MapMovementMessage(packet)
        if packet.actorId < 0 then
            --Print("MapMovement")
            if MONSTERS_TO_ATTACK.contextualId == packet.actorId then
                --Print("MapMov ReAdd Sorted")
                local tmp = MONSTERS_TO_ATTACK
                tmp.cellId = packet.keyMovements[2]
                table.insert(SORTED_MONSTERS, tmp)
            else
                for _, v in pairs(SORTED_MONSTERS) do
                    if v.contextualId == packet.actorId then
                        --Print("Monster updated")
                        v.cellId = packet.keyMovements[2]
                        break
                    end
                end
            end
        end
    end

    function CB_ContextRemoveElementMessage(packet)
        --Print("ContextRemove")
        for i = #SORTED_MONSTERS, 1, -1 do
            if SORTED_MONSTERS[i].contextualId == packet.id then
                --Print("Monster removed")
                table.remove(SORTED_MONSTERS, i)
                break
            end
        end
    end

    function CB_FightStartingMessage()
        SORTED_MONSTERS = {}
    end

-- Tri FightPacket

    function Get_SortedGroupMonster(pActors)
        local staticInfo = Get_GroupMonsterStaticInfo(Get_GroupMonsterInfo(pActors))
        local tbl = {}

        for i, tblGroupMonster in pairs(staticInfo) do
            local groupMonster = {}
            groupMonster.idMonster = {}
            groupMonster.cellId = tblGroupMonster.cellId
            groupMonster.contextualId = tblGroupMonster.contextualId

            for _, tblMonster in pairs(tblGroupMonster.Infos) do
                table.insert(groupMonster.idMonster, tblMonster.mainCreatureLightInfos.genericId)

                for _, sTblMonster in pairs(tblMonster.underlings) do
                    table.insert(groupMonster.idMonster, sTblMonster.genericId)
                end

            end
            table.insert(tbl, groupMonster)
        end
        return tbl
    end

    function Get_GroupMonsterInfo(pActors)
        local tbl = {}

        for _, v in pairs(pActors) do
            if developer:typeOf(v) == "GameRolePlayGroupMonsterInformations" then
                table.insert(tbl, v)
            end
        end
        
        return tbl
    end

    function Get_GroupMonsterStaticInfo(groupMonsterInfo)
        local tbl = {}

        for _, v in pairs(groupMonsterInfo) do
            local infos = {}
            infos.Infos = {}

            infos.contextualId = v.contextualId
            infos.cellId = v.disposition.cellId
            table.insert(infos.Infos, v.Infos)
            table.insert(tbl, infos)
        end

        return tbl
    end
-- Gestion Config monsters

    function AddMonsterConf(idMonster, min, max)
        local ins = { idMonster = idMonster , min = min, max = max }
        table.insert(MONSTERS_CONF, ins)
        Print(Get_NameMonster(idMonster).." Ajoutée a la configuration", "Conf")
    end

    function DelMonsterConf(idMonster)
        for i = #MONSTERS_CONF, 1, -1 do
            if MONSTERS_CONF[i].idMonster == idMonster then
                Print(Get_NameMonster(idMonster).." Supprimé de la configuration", 'Conf')
                table.remove(MONSTERS_CONF, i)
                break
            end
        end
    end

    function EditMonsterConf(idMonster, min, max)
        for _, v in pairs(MONSTERS_CONF) do
            if v.idMonster == idMonster then
                if min ~= nil then
                    v.min = min
                end
                if max ~= nil then
                    v.max = max
                end
                Print(Get_NameMonster(idMonster).." Modifié dans la configuration", "Conf")
                break
            end
        end
    end

    function ClearMonsterConf()
        MONSTERS_CONF = {}
        Print("Configuration monstres réinitialiser", "Conf")
    end

-- Appel API

    function Get_NameMonster(id)
        return id
    end

-- Utilitaire

    function Print(msg, header, msgType)
        local prefabStr = ""

        if header ~= nil then
            prefabStr = "["..string.upper(header).."] "..msg
        else
            prefabStr = msg
        end

        if msgType == nil then
            global:printSuccess(prefabStr)
        elseif string.lower(msgType) == "normal" then
            global:printMessage(prefabStr)
        elseif string.lower(msgType) == "error" then
            global:printError("[ERROR]["..header.."] "..msg)
        end
    end

    function CountIdenticValue(tbl, value)
        local count = 0
        for _, v in pairs(tbl) do
            if v == value then
                count = count + 1
            end
        end
        return count
    end