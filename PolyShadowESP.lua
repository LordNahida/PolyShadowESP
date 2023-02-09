local RunService = game:GetService("RunService");
local Workspace = game:GetService("Workspace");
local Players = game:GetService("Players");
local LPlayer = Players.LocalPlayer;

local Camera = Workspace.CurrentCamera;

local function Shift(CF, Magnitude)
    return CF.Position + (CF.RightVector * Magnitude.X) + (CF.UpVector * Magnitude.Y) + (CF.LookVector * Magnitude.Z);
end;
-- Converts a part into a table of edges consisting of 2 vertices (2 Vector3 values.)
local function GetCharacterVertices(Part)
    if (Part:IsA("Model")) then Part = Part.HumanoidRootPart; end;
    local CF = Part.CFrame;
    return {
        -- Head
        {Shift(CF, Vector3.new(-0.5, 1)), Shift(CF, Vector3.new(-0.5, 2))};
        {Shift(CF, Vector3.new(-0.5, 2)), Shift(CF, Vector3.new(0.5, 2))};
        {Shift(CF, Vector3.new(0.5, 2)), Shift(CF, Vector3.new(0.5, 1))};
        -- Right Arm
        {Shift(CF, Vector3.new(0.5, 1)), Shift(CF, Vector3.new(2, 1))};
        {Shift(CF, Vector3.new(2, 1)), Shift(CF, Vector3.new(2, -1))};
        {Shift(CF, Vector3.new(2, -1)), Shift(CF, Vector3.new(1, -1))};
        -- Feet
        {Shift(CF, Vector3.new(1, -1)), Shift(CF, Vector3.new(1, -3))};
        {Shift(CF, Vector3.new(1, -3)), Shift(CF, Vector3.new(-1, -3))};
        {Shift(CF, Vector3.new(-1, -3)), Shift(CF, Vector3.new(-1, -1))};
        -- Left Arm
        {Shift(CF, Vector3.new(-1, -1)), Shift(CF, Vector3.new(-2, -1))};
        {Shift(CF, Vector3.new(-2, -1)), Shift(CF, Vector3.new(-2, 1))};
        {Shift(CF, Vector3.new(-2, 1)), Shift(CF, Vector3.new(-0.5, 1))};
    }
end;
-- Draws a line for a single frame.
local function DrawLine(P0, P1, C)
    local Line = Drawing.new("Line");
    Line.Visible = true;
    Line.Thickness = 2;
    Line.Color = C or Color3.fromHex("#A5C73A");
    Line.Transparency = 1;

    Line.From = Vector2.new(P0.X, P0.Y);
    Line.To = Vector2.new(P1.X, P1.Y);
    spawn(function()
        RunService.Heartbeat:Wait();
        Line:Remove();
    end);
    return Line;
end;

local function SimplifyVector(Value)
    return Vector2.new(Value.X, Value.Y);
end;

-- Math stuff incoming
-- Converts lines that pass through P0 and P1 into [Ax + By + C = 0] form. This is so that we can easily get the intersection.
local function GetLineComponents(P0, P1)
    local X1, Y1, X2, Y2 = P0.X, P0.Y, P1.X, P1.Y;
    local A = Y1 - Y2;
    local B = X2 - X1;
    local C = X1 * Y2 - X2 * Y1;

    return A, B, C;
end;
-- Gets the intersection of 2 lines to determine where the angle break happens.
local function GetIntersection(L0, L1)
    local A1, B1, C1 = GetLineComponents(L0[1], L0[2]);
    local A2, B2, C2 = GetLineComponents(L1[1], L1[2]);
    local Denominator = (A1*B2-A2*B1);
    local X = (B1*C2-B2*C1)/Denominator;
    local Y = (C1*A2-C2*A1)/Denominator;
    return Vector3.new(X, Y, L0[1].Z);
end;
-- Gets the slope of a line. It's used to detect whether an angle break happens or not.
local function GetSlope(Line)
    local P0, P1 = Line[1], Line[2];
    return (P1.Y - P0.Y) / (P1.X - P0.X);
end;
local function CompareSlope(L0, L1)
    return (math.abs(GetSlope(L0) - GetSlope(L1)) < 0.01);
end;
-- Returns a point between the Start and the End that depends on T.
local function MapVertex(Start, End, T)
    return (Start * (1 - T)) + (End * T);
end;
-- Checks whether an intersection point is valid or not.
local function CheckMidPoint(Start, End, MidPoint)
    Start, End, MidPoint = SimplifyVector(Start), SimplifyVector(End), SimplifyVector(MidPoint);
    local Magnitude = (End - Start).Magnitude;
    local LDist = math.max((Start - MidPoint).Magnitude, (End - MidPoint).Magnitude);
    return LDist < Magnitude;
end;
--End of math suff finally.

-- Projection stuff
local Source, Filter;-- These are used as parameters for every projection function, so it's best to make the variables than to make them parameters.
-- Projects a 3D point to 2D based from the Source's perspective.
local function ProjectPoint(Point)
    local Ray = Ray.new(Source, (Point - Source)).Unit;
    Point = Workspace:Raycast(Ray.Origin, Ray.Direction * 1e5, Filter);
    Point = (Point and Point.Position) or (Ray.Origin + Ray.Direction * 1e5);
    Point = Camera:WorldToViewportPoint(Point);
    return Point;
end;
-- Gets the extension of the line at T.
local function ExtendLineAtT(Line, T)
    local Start, End = Line[1], Line[#Line];
    if (type(Start) == "table") then Start, End = Start[3], End[3]; end;
    Start, End = MapVertex(Start, End, T), MapVertex(Start, End, T + 0.0025);
    return {ProjectPoint(Start), ProjectPoint(End)};
end;

local function CompareNum(N0, N1, MaxDelta)
    return (math.abs(N1 - N0) <= MaxDelta);
end;

local function BufferEdge(Edge, BPE)
    local PreviousSegment = ExtendLineAtT(Edge, 0);
    local PreviousSlope = GetSlope(PreviousSegment);
    local EndSegment = ExtendLineAtT(Edge, 1);
    local Output = {PreviousSegment[1]};
    if (CompareNum(PreviousSlope, GetSlope(ExtendLineAtT(Edge, 1)), 0.01)) then Output[2] = EndSegment[1]; return Output; end;
    local MidPoint = GetIntersection(PreviousSegment, EndSegment);
    if (CheckMidPoint(PreviousSegment[1], EndSegment[1], MidPoint)) then
        Output[2] = MidPoint;
        Output[3] = EndSegment[1];
        return Output;
    elseif (BPE <= 1) then
        Output[2] = EndSegment[1];
        return Output;
    end;
    for Buffer = 1, BPE do
        local Segment = ExtendLineAtT(Edge, Buffer / BPE);
        local Slope = GetSlope(Segment);
        if (CompareNum(PreviousSlope, Slope, 0.01)) then
            PreviousSegment, PreviousSlope = Segment, Slope;
            continue;
        end;
        local MidPoint = GetIntersection(PreviousSegment, Segment);
        if (CheckMidPoint(PreviousSegment[1], Segment[1], MidPoint)) then
            Output[#Output + 1] = MidPoint;
        else
            Output[#Output + 1] = Segment[1];
        end;
        PreviousSegment = Segment;
    end;
    Output[#Output + 1] = EndSegment[1];
    return Output;
end;

-- Draws a table of 2D points
local function DrawComplexLine(Line)
    Line = BufferEdge(Line, 2);-- Intersecting lines tables
    local Start = Line[1];
    for Ldx = 2, #Line do
        local End = Line[Ldx];
        DrawLine(Start, End);
        Start = End;
    end;
end;

if (_G.Connection) then _G.Connection:Disconnect(); end;

Filter = RaycastParams.new();
local function RenderPlayer(Player)
    if (Player == LPlayer) then return; end;
    Source = LPlayer.Character.PrimaryPart.Position;
    Filter.FilterType = Enum.RaycastFilterType.Blacklist;
    Filter.FilterDescendantsInstances = {Player.Character, LPlayer.Character};
    Player = Player.Character:FindFirstChild("HumanoidRootPart");
    if (not Player) then return; end;
    local _, OnScreen = Camera:WorldToViewportPoint(Player.Position);
    if (not OnScreen) then return; end;
    if (Workspace:Raycast(Source, Player.Position, Filter)) then return; end;
    -- Player is on screen and not hidden behind a wall.
    local VertexData = GetCharacterVertices(Player);
    for _ = 1, #VertexData do
        DrawComplexLine(VertexData[_]);
    end;
    VertexData = nil;
end;

_G.Connection = RunService.Heartbeat:Connect(function()
    for _, Player in pairs(Players:GetPlayers()) do
        pcall(RenderPlayer, Player);
    end;
end);