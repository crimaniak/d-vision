module java.tostring;

T toImpl(T, S)(S value)
    if (is(T == string) && is(typeof(&S.toString) == string function()))
{
    return S.toString;
}
