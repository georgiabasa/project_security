#define U_EAX 7

extern unsigned int uctx_get(unsigned int, unsigned int);
extern unsigned int get_curid(void);

unsigned int uctx_arg1()
{
    unsigned int curid;
    unsigned int arg;
    curid = get_curid();
    arg = uctx_get(curid, U_EAX);
    return arg;
}
