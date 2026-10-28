using Jieliu.Core;

internal static class SelectionChecks
{
    public static void Run()
    {
        var keyboard=Enumerable.Range(0,8).Select(_=>Guid.NewGuid()).ToArray();
        Guid? current=keyboard[0]; var extended=new HashSet<Guid> { keyboard[0] };
        for (var step=0;step<3;step++) SelectionRules.Move(keyboard,extended,ref current,1,true);
        if (!extended.SetEquals(keyboard.Take(4))) throw new Exception("Consecutive Shift+Right did not advance");
        extended.Clear(); extended.Add(keyboard[3]); current=keyboard[3];
        for (var step=0;step<3;step++) SelectionRules.Move(keyboard,extended,ref current,-1,true);
        if (!extended.SetEquals(keyboard.Take(4))) throw new Exception("Consecutive Shift+Left did not advance");
        current=keyboard[6]; SelectionRules.Move(keyboard,extended,ref current,1,false);
        if (!extended.SetEquals(new[] { keyboard[7] })) throw new Exception("Arrow retained previous multi-selection");
        SelectionRules.Move(keyboard.Take(4).ToArray(),extended,ref current,1,false);
        if (!extended.SetEquals(new[] { keyboard[0] })) throw new Exception("Evicted keyboard position was reused");
        static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
        var ids = Enumerable.Range(0, 9).Select(_ => Guid.NewGuid()).ToArray();
        foreach (var shift in new[] { false, true })
        foreach (var control in new[] { false, true })
        {
            var selected = new HashSet<Guid> { ids[1] }; Guid? anchor = ids[1];
            Check(!SelectionRules.Apply(ids.Skip(1).ToArray(), selected, ids[0], ref anchor, shift, control), "Evicted target must be rejected");
            Check(selected.SetEquals(new[] { ids[1] }) && anchor == ids[1], "Stale release must preserve surviving selection/anchor");
        }
        var selection = new HashSet<Guid>(); Guid? first = ids[0];
        Check(SelectionRules.Apply(ids, selection, ids[2], ref first, true, false) && selection.SetEquals(ids.Take(3)), "Shift range changed");
        selection.Clear(); first = ids[8];
        Check(SelectionRules.Apply(ids.Take(8).ToArray(), selection, ids[3], ref first, true, false) && selection.SetEquals(new[] { ids[3] }), "Evicted anchor must fall back to target");
        selection.Clear(); first = null;
        foreach (var id in ids.Take(8)) SelectionRules.Apply(ids, selection, id, ref first, false, true);
        Check(selection.Count == 8, "Control multi-selection changed");
        SelectionRules.Apply(ids, selection, ids[0], ref first, false, true);
        Check(selection.Count == 7 && !selection.Contains(ids[0]), "Control toggle changed");
        SelectionRules.Apply(ids, selection, ids[7], ref first, false, false);
        Check(selection.SetEquals(new[] { ids[7] }), "Plain selection must collapse to target");
        Console.WriteLine("PASS: evicted release with all modifiers, surviving selection, missing anchor, range and toggle selection");
        var history = new History();
        var captures = ids.Select((id, i) => new Capture(id, $"slot-{i}.png", DateTime.UnixEpoch, 40, 30)).ToArray();
        foreach (var capture in captures.Take(5)) history.Insert(capture);
        SelectionRules.Apply(history.Items.Select(c => c.Id).ToArray(), selection, captures[1].Id, ref first, false, false);
        history.Insert(captures[5]);
        Check(history.Slots[5] == captures[5].Id && history.Slots[1] == captures[1].Id && history.WritePointer == 6, "Selecting slot 2 changed next write from slot 6");
        foreach (var capture in captures.Skip(6)) history.Insert(capture);
        Check(history.Slots[0] == captures[8].Id && history.WritePointer == 1, "Ring did not wrap independently of selection");
        Console.WriteLine("PASS: selection independent of slot write pointer and ring wrap");
    }
}
