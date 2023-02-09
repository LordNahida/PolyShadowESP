local RunService = game:GetService("RunService");
local Workspace = game:GetService("Workspace");
local Players = game:GetService("Players");
local Player = Players.LocalPlayer;
local Mouse = Player:GetMouse();

local Camera = Workspace.CurrentCamera;
local Target = Workspace.Target;

-- Converts a part into a table of edges consisting of 2 vertices (2 Vector3 values.)
local function GetVertexData(Part)
    if (Part:IsA("Model")) then
        Part = Part.PrimaryPart;
    end;

    local Center = Part.CFrame;
    local Size = Part.Size / 2;
    local Offset = (Center.RightVector * Size.X) + (Center.UpVector * Size.Y) + (Center.LookVector * Size.Z);
    Center = Center.Position;
    local MaxPoint = Center + Offset;
    local MinPoint = Center - Offset;

    local NX = Vector3.new(MaxPoint.X, MinPoint.Y, MinPoint.Z);
    local NY = Vector3.new(MinPoint.X, MaxPoint.Y, MinPoint.Z);
    local NZ = Vector3.new(MinPoint.X, MinPoint.Y, MaxPoint.Z);

    local XX = Vector3.new(MinPoint.X, MaxPoint.Y, MaxPoint.Z);
    local XY = Vector3.new(MaxPoint.X, MinPoint.Y, MaxPoint.Z);
    local XZ = Vector3.new(MaxPoint.X, MaxPoint.Y, MinPoint.Z);
    return
    {
        -- Bottom Square
        {MinPoint, NX};
        {NX, XY};
        {XY, NZ};
        {NZ, MinPoint};
        -- Vertical Lines
        {MinPoint, NY};
        {NX, XZ};
        {NZ, XX};
        {XY, MaxPoint};
        -- Top Square
        {MaxPoint, XX};
        {XX, NY};
        {NY, XZ};
        {XZ, MaxPoint};
    };
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
        RunService.RenderStepped:Wait();
        Line:Remove();
    end);
    return Line;
end;
-- Turns Vector3 to Vector2
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
-- Old Buffering function. It's bound to get all surfaces given enough time, but is pretty slow.
do local function BufferEdge(Edge, MinT, StartSegment, StartSlope, MaxT, EndSegment, EndSlope)
    MinT, MaxT = MinT or 0, MaxT or 1;
    StartSegment, EndSegment = StartSegment or ExtendLineAtT(Edge, MinT), EndSegment or ExtendLineAtT(Edge, MaxT);
    StartSlope, EndSlope = StartSlope or GetSlope(StartSegment), EndSlope or GetSlope(EndSegment);
    local Output = {StartSegment[1], EndSegment[1]};
    local InsertIndex = 2;
    local Step, CT = 0.1, MinT;
    if (CompareNum(StartSlope, EndSlope, 0.01)) then return Output; end;
    local MidPoint = GetIntersection(StartSegment, EndSegment);
    if (CheckMidPoint(StartSegment[1], EndSegment[1], MidPoint)) then return {StartSegment[1], MidPoint, EndSegment[1]}; end;
    while (true) do
        while (true) do
            CT = CT + Step;
            if (Step < 1 / 1e5) then return Output; end;
            if (CT >= 1) then return Output; end;
            local CLine = ExtendLineAtT(Edge, CT);
            local CSlope = GetSlope(CLine);
            if (CompareNum(StartSlope, CSlope, 0.01)) then continue; end;
            if (CompareNum(EndSlope, CSlope, 0.01)) then break; end;
            local StartInt = GetIntersection(StartSegment, CLine);
            if (CheckMidPoint(StartSegment[1], CLine[1], StartInt)) then
                StartSegment = CLine;
                StartSlope = CSlope;
                table.insert(Output, #Output - 1, StartInt);
                StartInt = true;
            end;
            local EndInt = GetIntersection(EndSegment, CLine);
            if (CheckMidPoint(EndSegment[1], CLine[1], EndInt)) then
                if (StartInt == true) then table.insert(Output, InsertIndex, EndInt); return Output; end;
                break;
            end;
        end;
        CT = CT - Step;
        Step = Step / 10;
    end;
end; end;
-- New Buffering function. It buffers surfaces based on a given step value, BPE (Buffers Per Edge).
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
    Line = BufferEdge(Line, 10);-- Intersecting lines tables
    local Start = Line[1];
    for Ldx = 2, #Line do
        local End = Line[Ldx];
        DrawLine(Start, End);
        Start = End;
    end;
end;