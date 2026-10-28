namespace Jieliu.Core;

public static class SelectionRules
{
    public static bool Move(IReadOnlyList<Guid> ordered,HashSet<Guid> selection,ref Guid? current,int offset,bool extend)
    {
        if (ordered.Count==0) return false;
        var index=current is { } id ? ordered.ToList().IndexOf(id) : -1;
        var next=Math.Clamp(index+offset,0,ordered.Count-1);
        if (!extend) selection.Clear();
        current=ordered[next]; selection.Add(ordered[next]); return true;
    }
    // Resolve against the current history, never against a mouse-down snapshot.
    public static bool Apply(IReadOnlyList<Guid> ordered, HashSet<Guid> selection, Guid target,
        ref Guid? anchor, bool shift, bool control)
    {
        var ids = ordered.ToList();
        var b = ids.IndexOf(target);
        if (b < 0) return false;
        if (shift && anchor is { } first)
        {
            var a = ids.IndexOf(first);
            if (a >= 0)
                for (var i = Math.Min(a, b); i <= Math.Max(a, b); i++) selection.Add(ids[i]);
            else selection.Add(target);
        }
        else if (control)
        { if (!selection.Add(target)) selection.Remove(target); anchor = target; }
        else { selection.Clear(); selection.Add(target); anchor = target; }
        return true;
    }
}
